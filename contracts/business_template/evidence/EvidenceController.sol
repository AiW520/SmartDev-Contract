/*
 * Copyright 2014-2019 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * */

pragma solidity ^0.4.25;

import "./RequestRepository.sol";
import "./EvidenceRepository.sol";

/**
 * @title  存证控制器（编排层）
 * @dev    作为存证模块的门面合约，编排 RequestRepository（投票流程）和 EvidenceRepository（数据存储）
 *         之间的协作。用户直接与此合约交互，无需了解底层仓库合约的细节。
 *
 *         完整业务流程：
 *         ```
 *         1. 用户调用 createSaveRequest(hash, ext) 发起存证请求
 *         2. 投票人依次调用 voteSaveRequest(hash) 进行投票
 *         3. 当投票数 >= 阈值时，自动执行：
 *            - 将存证数据写入 EvidenceRepository
 *            - 删除 RequestRepository 中的请求（释放存储）
 *            - 触发 EvidenceSaved 事件
 *         ```
 *
 *         依赖关系：
 *         - RequestRepository：管理创建、投票、删除请求
 *         - EvidenceRepository：存储已通过的存证数据
 */
contract EvidenceController {

    /// @notice 请求仓库合约实例
    RequestRepository public _requestRepo;

    /// @notice 存证数据仓库合约实例
    EvidenceRepository public _evidenceRepo;

    // ============================================================
    //  事件
    // ============================================================

    /// @notice 创建存证请求时触发
    event CreateSaveRequest(bytes32 indexed hash, address creator);

    /// @notice 投票时触发（无论是否达到阈值）
    event VoteSaveRequest(bytes32 indexed hash, address voter, bool passed);

    /// @notice 存证成功写入时触发
    event EvidenceSaved(bytes32 indexed hash);

    // ============================================================
    //  构造函数
    // ============================================================

    /**
     * @notice  初始化存证系统：部署底层仓库合约
     * @dev     内部创建 RequestRepository 和 EvidenceRepository 两个子合约。
     * @param   threshold   投票通过所需的最小票数
     * @param   voterArray  初始投票人地址列表
     */
    constructor(uint8 threshold, address[] memory voterArray) public {
        _requestRepo = new RequestRepository(threshold, voterArray);
        _evidenceRepo = new EvidenceRepository();
    }

    // ============================================================
    //  修饰器
    // ============================================================

    /**
     * @notice  验证哈希值非空
     * @dev     防止传入 bytes32(0) 导致存在性校验失效
     */
    modifier validateHash(bytes32 hash) {
        require(hash != bytes32(0), "EvidenceController: invalid hash");
        _;
    }

    // ============================================================
    //  存证流程
    // ============================================================

    /**
     * @notice  第一步：创建存证请求
     * @dev     将请求委托给 RequestRepository。请求创建后进入"待投票"状态。
     * @param   hash  存证内容的哈希值（不得为 0）
     * @param   ext   扩展数据，可由业务层自定义编码
     */
    function createSaveRequest(bytes32 hash, bytes memory ext) public validateHash(hash) {
        _requestRepo.createSaveRequest(hash, msg.sender, ext);
        emit CreateSaveRequest(hash, msg.sender);
    }

    /**
     * @notice  第二步：对存证请求进行投票
     * @dev     投票成功后检查是否达到阈值。若达到，自动执行存证写入和请求清理。
     *          返回值 true 仅表示投票操作执行成功，不代表存证已通过。
     *          需通过监听 VoteSaveRequest 事件中的 `passed` 字段判断是否达成阈值。
     * @param   hash  存证请求的哈希值
     * @return  bool  true 表示投票操作成功，false 表示投票被 _requestRepo 否决
     */
    function voteSaveRequest(bytes32 hash) public validateHash(hash) returns (bool) {
        // 委托给 RequestRepository 执行投票
        bool success = _requestRepo.voteSaveRequest(hash, msg.sender);
        if (!success) {
            return false;
        }

        // 获取投票后的最新状态
        (, , , uint8 voted, uint8 threshold) = _requestRepo.getRequestData(hash);
        bool passed = voted >= threshold;

        emit VoteSaveRequest(hash, msg.sender, passed);

        // 达成阈值：写入存证 → 删除请求 → 触发存证事件
        if (passed) {
            _evidenceRepo.setData(hash, msg.sender, now);
            _requestRepo.deleteSaveRequest(hash);
            emit EvidenceSaved(hash);
        }

        return true;
    }

    // ============================================================
    //  查询接口
    // ============================================================

    /**
     * @notice  查询存证请求的详细信息
     * @param   hash      请求哈希
     * @return  bytes32   请求哈希
     * @return  creator   请求创建者
     * @return  ext       扩展数据
     * @return  voted     当前已投票数
     * @return  threshold 投票通过阈值
     */
    function getRequestData(bytes32 hash)
        public
        view
        returns (bytes32, address creator, bytes memory ext, uint8 voted, uint8 threshold)
    {
        return _requestRepo.getRequestData(hash);
    }

    /**
     * @notice  查询已存证的数据
     * @dev     仅返回已通过投票并写入 EvidenceRepository 的存证记录。
     *          若请求仍在投票中尚未通过，调用此函数将返回空数据。
     * @param   hash      存证哈希
     * @return  bytes32   存证哈希
     * @return  address   存证所有者
     * @return  uint      存证时间戳
     */
    function getEvidence(bytes32 hash)
        public
        view
        returns (bytes32, address, uint)
    {
        return _evidenceRepo.getData(hash);
    }
}