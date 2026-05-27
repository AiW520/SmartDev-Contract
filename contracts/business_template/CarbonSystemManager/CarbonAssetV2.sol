// SPDX-License-Identifier: MIT
pragma solidity ^0.4.25;
pragma experimental ABIEncoderV2;

import "./CarbonExcitationV2.sol";
import "./SafeMath.sol";

/**
 * @title  碳资产交易合约 V2
 * @dev    碳交易系统的核心合约，管理碳排放额度的买卖、排放申请与审批、碳积分激励。
 *         继承链：Ownable → CarbonCertificationV2 → CarbonExcitationV2 → CarbonAssetV2
 *
 *         核心业务流程：
 *         ```
 *         1. 企业注册 → 上传资质 → 监管机构审核 → 获得排放额度
 *         2. 企业出售额度 → 其他企业购买
 *         3. 企业申请排放 → 监管审批 → 实际排放/超额罚款
 *         4. 每月清零 + 发放新额度（周期性管理）
 *         ```
 *
 *         数据结构：
 *         - EmissionResource：排放申请记录
 *         - EAsset：企业出售碳资产记录
 *         - Transaction：碳额度交易记录（继承自 CarbonCertificationV2）
 */
contract CarbonAssetV2 is CarbonExcitationV2 {

    using SafeMath for *;

    // ============================================================
    //  数据结构
    // ============================================================

    /// @notice 碳排放资源申请
    struct EmissionResource {
        uint256 emissionId;          // 申请 ID
        address enterpriseAddress;   // 申请企业地址
        uint256 emissions;           // 申请排放量
        string  description;         // 排放描述
        bool    isApprove;           // 是否已审批
        uint256 time;                // 排放时间（实际排放后写入）
    }

    /// @notice 企业出售碳资产
    struct EAsset {
        uint assetId;                // 出售记录 ID
        address assetAddress;        // 出售方地址
        uint256 assetQuantity;       // 出售数量
        uint256 assetAmount;         // 出售单价
        uint256 time;                // 上架时间
    }

    // ============================================================
    //  状态变量
    // ============================================================

    /// @notice 碳资产出售计数器
    uint256 public eassetCount;

    /// @notice 排放资源申请计数器
    uint256 public emissionResourceCount;

    /// @notice ID → 碳资产出售记录
    mapping(uint256 => EAsset) public eassetMap;

    /// @notice 地址 → 最近出售记录 ID
    mapping(address => uint256) public eassetIndex;

    /// @notice ID → 排放资源申请
    mapping(uint256 => EmissionResource) public idToEmissionMap;

    /// @notice 全部碳资产出售记录（冗余存储，供分页查询使用）
    EAsset[] public eassets;

    /// @notice 全部排放资源申请（冗余存储，供分页查询使用）
    EmissionResource[] public emissionResources;

    // ============================================================
    //  事件
    // ============================================================

    event EnterpriseEmissionUpload(
        address indexed _enterpriseAddr,
        uint256 indexed _emissionEmission
    );
    event VerifyEnterpriseEmission(address indexed _enterpriseAddr);
    event UpdateEnterpriseEmission(
        address indexed _enterpriseAddr,
        uint256 indexed _totalEmissions
    );
    event EnterpriseEmission(
        address indexed _enterpriseAddr,
        uint256 indexed _emissionEmission,
        bool indexed _isCompulsion
    );

    // ============================================================
    //  构造函数
    // ============================================================

    constructor() public {
        registerRegulator(msg.sender, "监管机构");
    }

    // ============================================================
    //  修饰器
    // ============================================================

    /**
     * @notice  检查企业是否已通过认证审核
     * @param   _enterpriseAddr  企业地址
     */
    modifier CheckVerify(address _enterpriseAddr) {
        require(
            checkEnterpriseVerified(_enterpriseAddr),
            "CarbonAsset: enterprise not verified"
        );
        _;
    }

    // ============================================================
    //  碳额度交易
    // ============================================================

    /**
     * @notice  企业购买碳排放额度
     * @dev     买方（msg.sender）从卖方（_enterpriseAddr）购买指定数量的碳额度。
     *          买卖双方均需已认证。购买后自动记录交易并触发 TransferEmissionLimit 事件。
     *          注意：eassetMap 和 eassets 数组需保持同步更新。
     * @param   _enterpriseAddr  卖方企业地址
     * @param   eassetId         碳资产出售记录 ID
     * @param   _quantity        购买数量
     * @return  Transaction      交易记录
     */
    function buyEmissionLimit(address _enterpriseAddr, uint256 eassetId, uint256 _quantity)
        public
        OnlyEnterprice(msg.sender)
        CheckVerify(msg.sender)
        returns (Transaction memory)
    {
        require(_enterpriseAddr != msg.sender, "CarbonAsset: cannot buy from self");

        Enterprise storage buyer = enterpriseMap[msg.sender];
        Enterprise storage seller = enterpriseMap[_enterpriseAddr];
        EAsset storage easset = eassetMap[eassetId];

        require(easset.assetQuantity > 0, "CarbonAsset: sold out");
        require(easset.assetQuantity >= _quantity, "CarbonAsset: quantity exceeds available");

        // 计算交易金额并划转
        uint256 totalCost = SafeMath.mul(_quantity, easset.assetAmount);
        buyer.enterpriseBalance -= totalCost;
        buyer.qualification.qualificationEmissionLimit += _quantity;
        seller.enterpriseBalance += totalCost;

        // 记录交易
        transactionCount++;
        uint256 transactionId = transactionCount;
        Transaction storage _transaction = transactionMap[transactionId];
        _transaction.transactionId = transactionId;
        _transaction.transactionOrderName = "碳额度企业交易";
        _transaction.transactionBuyAddress = buyer.enterpriseAddress;
        _transaction.transactionSellAddress = seller.enterpriseAddress;
        _transaction.transactionTime = block.timestamp;
        _transaction.transactionQuantity = _quantity;

        enterpriseToTransactions[msg.sender].push(_transaction);
        transactionList.push(_transaction);

        // 同步更新映射和数组中的资产数量
        easset.assetQuantity -= _quantity;
        uint length = eassets.length;
        for (uint i = 0; i < length; ++i) {
            if (eassets[i].assetId == eassetId) {
                eassets[i].assetQuantity -= _quantity;
                break;
            }
        }

        emit TransferEmissionLimit(_enterpriseAddr, buyer.enterpriseAddress, _quantity);
        return _transaction;
    }

    /**
     * @notice  企业出售碳额度
     * @dev     出售方（msg.sender）上架指定数量的碳额度。成功后额度从企业账户扣除。
     * @param   _emissionLimitCount  出售的碳额度数量
     * @param   _amount              出售单价
     * @return  EAsset               出售记录
     */
    function sellEmissionLimit(uint256 _emissionLimitCount, uint256 _amount)
        public
        OnlyEnterprice(msg.sender)
        CheckVerify(msg.sender)
        returns (EAsset memory)
    {
        require(
            enterpriseMap[msg.sender].qualification.qualificationEmissionLimit >= _emissionLimitCount,
            "CarbonAsset: insufficient emission limit"
        );

        Enterprise storage _enterprise = enterpriseMap[msg.sender];
        _enterprise.qualification.qualificationEmissionLimit -= _emissionLimitCount;

        eassetCount++;
        uint256 eassetId = eassetCount;

        EAsset storage _newEasset = eassetMap[eassetId];
        _newEasset.assetId = eassetId;
        _newEasset.assetAddress = msg.sender;
        _newEasset.assetQuantity = _emissionLimitCount;
        _newEasset.assetAmount = _amount;
        _newEasset.time = block.timestamp;

        eassets.push(_newEasset);
        eassetIndex[msg.sender] = eassetId;

        emit SellEmissionLimit(_emissionLimitCount, _amount);
        return _newEasset;
    }

    /**
     * @notice  更新已上架的碳资产出售信息
     * @dev     仅更新 eassetMap；注意：此操作不会同步更新 eassets 数组中的对应项。
     *          如需保证数组一致性，建议调用方同步维护。
     * @param   _eassetId            出售记录 ID
     * @param   _emissionLimitCount  新的出售数量
     * @param   _amount              新的单价
     */
    function updateSellEmissionLimit(uint256 _eassetId, uint256 _emissionLimitCount, uint256 _amount) public {
        EAsset storage _easset = eassetMap[_eassetId];
        _easset.assetQuantity = _emissionLimitCount;
        _easset.assetAmount = _amount;
    }

    // ============================================================
    //  排放申请与审批
    // ============================================================

    /**
     * @notice  企业提交排放申请
     * @dev     申请数量不能超过企业当前持有的碳额度。申请提交后进入"待审批"状态。
     * @param   _enterpriseAddr     申请企业地址
     * @param   _emissionEmission   申请排放量
     * @param   _description        排放描述
     * @return  EmissionResource    排放申请记录
     */
    function enterpriseEmissionUpload(
        address _enterpriseAddr,
        uint256 _emissionEmission,
        string memory _description
    )
        public
        CheckVerify(msg.sender)
        returns (EmissionResource memory)
    {
        require(
            _emissionEmission <= enterpriseMap[_enterpriseAddr].qualification.qualificationEmissionLimit,
            "CarbonAsset: emission exceeds limit"
        );

        emissionResourceCount++;
        uint256 emissionResouceId = emissionResourceCount;

        EmissionResource storage emissionResource = idToEmissionMap[emissionResouceId];
        emissionResource.emissionId = emissionResouceId;
        emissionResource.enterpriseAddress = _enterpriseAddr;
        emissionResource.emissions = _emissionEmission;
        emissionResource.description = _description;
        emissionResource.isApprove = false;
        emissionResource.time = 0;

        emissionResources.push(emissionResource);

        emit EnterpriseEmissionUpload(msg.sender, _emissionEmission);
        return emissionResource;
    }

    /**
     * @notice  监管机构审批排放申请
     * @dev     更新审批状态并同步 eemarsResources 数组中的对应记录。
     * @param   _enterpriseAddr  企业地址（用于数组查找）
     * @param   _emmissionid     排放申请 ID
     * @param   _isApprove       是否批准
     * @return  bool             true = 批准，false = 拒绝
     */
    function verifyEnterpriseEmission(address _enterpriseAddr, uint256 _emmissionid, bool _isApprove)
        public
        returns (bool)
    {
        EmissionResource storage emissionResource = idToEmissionMap[_emmissionid];
        emissionResource.isApprove = _isApprove;

        // 同步更新 eemarsResources 数组中对应的记录
        for (uint i = 0; i < emissionResources.length; ++i) {
            if (emissionResources[i].enterpriseAddress == _enterpriseAddr) {
                emissionResources[i] = emissionResource;
                break;
            }
        }

        emit VerifyEnterpriseEmission(_enterpriseAddr);
        return _isApprove;
    }

    /**
     * @notice  更新企业的累计总排放量
     * @dev     用于周期性更新企业排放数据。
     * @param   _enterpriseAddr  企业地址
     * @param   _totalEmissions  要累加的总排放量
     * @return  bool             始终返回 true
     */
    function updateEnterpriseEmission(address _enterpriseAddr, uint256 _totalEmissions)
        public
        CheckVerify(msg.sender)
        returns (bool)
    {
        Enterprise storage enterprise = enterpriseMap[_enterpriseAddr];
        enterprise.enterpriseTotalEmission += _totalEmissions;

        emit UpdateEnterpriseEmission(_enterpriseAddr, _totalEmissions);
        return true;
    }

    /**
     * @notice  企业执行实际碳排放
     * @dev     分两种情况：
     *           - 强制排放（_isCompulsion = true）：超出额度部分按 EXCESS_BALANCE 单价罚款
     *           - 正常排放（_isCompulsion = false）：从企业总排放量和额度中扣除
     *           排放后将写入 time 字段，排放量清零（emissions = 0）。
     * @param   _emmissionid       排放申请 ID
     * @param   _emissionEmission  实际排放量
     * @param   _isCompulsion      是否强制排放（超额排放）
     * @return  EmissionResource   更新后的排放记录
     */
    function enterpriseEmission(uint256 _emmissionid, uint256 _emissionEmission, bool _isCompulsion)
        public
        CheckVerify(msg.sender)
        returns (EmissionResource memory)
    {
        require(
            enterpriseMap[msg.sender].enterpriseTotalEmission != 0,
            "CarbonAsset: total emission not updated"
        );

        Enterprise storage enterprise = enterpriseMap[msg.sender];
        EmissionResource storage emissionResource = idToEmissionMap[_emmissionid];

        require(emissionResource.emissions != 0, "CarbonAsset: emission quota exhausted");

        // 审批通过 或 排放量未超出审批额度
        require(
            emissionResource.isApprove || _emissionEmission <= emissionResource.emissions,
            "CarbonAsset: emission not approved or exceeds limit"
        );

        if (_isCompulsion) {
            // 超额强制排放：计算超额部分并罚款
            uint256 excessTotal = SafeMath.sub(
                _emissionEmission,
                enterprise.qualification.qualificationEmissionLimit
            );
            enterprise.enterpriseBalance -= SafeMath.mul(excessTotal, EXCESS_BALANCE);
            enterprise.qualification.qualificationEmissionLimit = 0;
            emissionResource.emissions = 0;
        } else {
            // 正常排放：扣减额度和总排放量
            enterprise.enterpriseTotalEmission -= _emissionEmission;
            enterprise.qualification.qualificationEmissionLimit -= _emissionEmission;
            emissionResource.emissions -= _emissionEmission;
        }

        enterprise.enterpriseOverEmission += _emissionEmission;
        emissionResource.time = block.timestamp;

        // 同步更新 eemarsResources 数组
        for (uint i = 0; i < emissionResources.length; ++i) {
            if (emissionResources[i].enterpriseAddress == msg.sender) {
                emissionResources[i] = emissionResource;
                break;
            }
        }

        emit EnterpriseEmission(msg.sender, _emissionEmission, _isCompulsion);
        return emissionResource;
    }

    // ============================================================
    //  批量管理（仅管理员）
    // ============================================================

    /**
     * @notice  月初清零所有企业的已排放量
     * @dev     遍历 enterprisesAddress 数组，将 enterpriseOverEmission 置零。
     *          建议仅由监管机构或合约 Owner 调用。
     */
    function clearOverEmissions() public {
        for (uint256 i = 0; i < enterprisesAddress.length; i++) {
            if (enterprisesAddress[i] != address(0)) {
                enterpriseMap[enterprisesAddress[i]].enterpriseOverEmission = 0;
            }
        }
    }

    /**
     * @notice  月初发放碳排放额度
     * @dev     为所有已注册企业增加指定的排放额度。
     *          建议仅由监管机构或合约 Owner 调用。
     * @param   _qualificationEmissionLimit  本次发放的额度数量
     */
    function initEmissionLimit(uint256 _qualificationEmissionLimit) public {
        for (uint256 i = 0; i < enterprisesAddress.length; i++) {
            if (enterprisesAddress[i] != address(0)) {
                enterpriseMap[enterprisesAddress[i]]
                    .qualification
                    .qualificationEmissionLimit += _qualificationEmissionLimit;
            }
        }
    }

    // ============================================================
    //  分页查询
    // ============================================================

    /**
     * @notice  分页查询企业出售碳资产记录
     * @param   page      页码（从 1 开始）
     * @param   pageSize  每页记录数
     * @return  EAsset[]  当前页的碳资产出售记录
     */
    function selectAllEnterpriseAssets(uint256 page, uint256 pageSize)
        public
        view
        returns (EAsset[] memory)
    {
        require(eassets.length != 0, "CarbonAsset: no assets to query");
        require(page > 0, "CarbonAsset: page must be > 0");

        uint256 startIndex = (page - 1) * pageSize;
        uint256 endIndex = startIndex + pageSize > eassets.length
            ? eassets.length
            : startIndex + pageSize;

        EAsset[] memory eAssetArr = new EAsset[](endIndex - startIndex);
        for (uint i = startIndex; i < endIndex; i++) {
            eAssetArr[i - startIndex] = eassets[i];
        }
        return eAssetArr;
    }

    /**
     * @notice  分页查询排放资源申请记录
     * @param   page      页码（从 1 开始）
     * @param   pageSize  每页记录数
     * @return  EmissionResource[]  当前页的排放申请记录
     */
    function queryAllEmissionResources(uint256 page, uint256 pageSize)
        public
        view
        returns (EmissionResource[] memory)
    {
        require(emissionResources.length != 0, "CarbonAsset: no emission resources");
        require(page > 0, "CarbonAsset: page must be > 0");

        uint256 startIndex = (page - 1) * pageSize;
        uint256 endIndex = startIndex + pageSize > emissionResources.length
            ? emissionResources.length
            : startIndex + pageSize;

        EmissionResource[] memory emissionResourceArr = new EmissionResource[](endIndex - startIndex);
        for (uint i = startIndex; i < endIndex; i++) {
            emissionResourceArr[i - startIndex] = emissionResources[i];
        }
        return emissionResourceArr;
    }

    // ============================================================
    //  单条查询
    // ============================================================

    /**
     * @notice  查询交易详细信息
     * @param   _transactionId  交易 ID
     * @return  Transaction     交易记录
     */
    function selectTransactionInfo(uint256 _transactionId)
        public
        view
        returns (Transaction memory)
    {
        return transactionMap[_transactionId];
    }

    /**
     * @notice  查询企业的碳积分余额
     * @return  uint256  碳积分数量
     */
    function queryEnterpriseCredit()
        public
        view
        CheckVerify(msg.sender)
        returns (uint256)
    {
        return enterpriseMap[msg.sender].enterpriseCarbonCredits;
    }

    /**
     * @notice  查询企业的已完成排放量
     * @param   _enterpriseAddr  企业地址
     * @return  uint256          已完成的排放量
     */
    function queryEnterpriseTotalEmission(address _enterpriseAddr)
        public
        view
        returns (uint256)
    {
        return enterpriseMap[_enterpriseAddr].enterpriseOverEmission;
    }

    /**
     * @notice  查询碳资产出售记录
     * @param   _eassetId  出售记录 ID
     * @return  EAsset     出售记录
     */
    function queryEnterpriseAssetInfo(uint256 _eassetId)
        public
        view
        returns (EAsset memory)
    {
        return eassetMap[_eassetId];
    }

    /**
     * @notice  查询排放申请记录
     * @param   _emmissionid  排放申请 ID
     * @return  EmissionResource  排放申请记录
     */
    function queryEnterpriseEmissionInfo(uint256 _emmissionid)
        public
        view
        returns (EmissionResource memory)
    {
        return idToEmissionMap[_emmissionid];
    }

    /**
     * @notice  查询已注册企业总数
     */
    function queryEnterprisesLength() public view returns (uint256) {
        return enterpriseList.length;
    }

    /**
     * @notice  查询监管机构总数
     */
    function queryRegulatorsLength() public view returns (uint256) {
        return regulatorList.length;
    }

    /**
     * @notice  查询交易记录总数
     */
    function queryTransactionsLength() public view returns (uint256) {
        return transactionList.length;
    }

    /**
     * @notice  查询排放申请总数
     */
    function queryEmissionResourcesLength() public view returns (uint256) {
        return emissionResources.length;
    }

    /**
     * @notice  查询碳资产出售记录总数
     */
    function queryEAssetsLength() public view returns (uint256) {
        return eassets.length;
    }

    // ============================================================
    //  测试辅助函数（仅用于开发调试，生产环境应移除）
    // ============================================================

    /// @dev 测试用：初始化天虹科技企业
    function initA() public {
        registerEnterprise(0xb33aa9beb22eb99ecf07ccf504c5bb722a6eabd1, "天虹科技");
        qualificationUpload("测试A", "测试A");
    }

    /// @dev 测试用：初始化弘安科技企业
    function initB() public {
        registerEnterprise(0xe899c3d457196fb9370ddb7f9c7ec197df5d10df, "弘安科技");
        qualificationUpload("测试B", "测试B");
    }

    /// @dev 测试用：初始化天湖科技企业
    function initC() public {
        registerEnterprise(0xff20ff1a1a30b8e07d6cf679166eee8d023b4519, "天湖科技");
        qualificationUpload("测试C", "测试C");
    }

    /// @dev 测试用：注册监管机构并批量审批三家企业
    function initO() public {
        registerRegulator(msg.sender, "监管机构");
        verifyQualification(0xb33aa9beb22eb99ecf07ccf504c5bb722a6eabd1, true);
        verifyQualification(0xe899c3d457196fb9370ddb7f9c7ec197df5d10df, true);
        verifyQualification(0xff20ff1a1a30b8e07d6cf679166eee8d023b4519, true);
    }

    /// @dev 测试用：初始化天虹科技的排放场景
    function initACAS() public {
        updateEnterpriseEmission(msg.sender, 25000);
        updateBalance(msg.sender, 10000);
        enterpriseEmissionUpload(msg.sender, 1000, "绿色排放");
    }

    /// @dev 测试用：初始化弘安科技的排放场景
    function initBCAS() public {
        updateEnterpriseEmission(msg.sender, 20000);
        updateBalance(msg.sender, 10000);
        enterpriseEmissionUpload(msg.sender, 1000, "绿色排放");
    }

    /// @dev 测试用：初始化天湖科技的排放场景
    function initCCAS() public {
        updateEnterpriseEmission(msg.sender, 18000);
        updateBalance(msg.sender, 10000);
        enterpriseEmissionUpload(msg.sender, 1000, "绿色排放");
    }

}