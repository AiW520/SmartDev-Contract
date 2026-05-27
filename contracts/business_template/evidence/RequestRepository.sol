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
 * limitations under the License.
 * */

pragma solidity ^0.4.25;

import "./Authentication.sol";

/**
 * @title  存证请求仓库
 * @dev    管理"创建存证请求 → 投票 → 达成阈值"的完整投票流程。
 *         继承 Authentication 合约，仅 Owner 或白名单地址可操作。
 *
 *         投票规则：
 *         - 任何授权地址（`auth` modifier）均可创建存证请求
 *         - 只有构造函数指定的投票人（`_voters`）可以投票
 *         - 每个投票人对同一请求只能投一票
 *         - 当投票数达到阈值（`_threshold`）时，由 EvidenceController 触发存证
 *
 *         状态转换：
 *         ```
 *         请求创建 → [投票中] → 票数 >= 阈值 → 删除请求 + 存证写入
 *         ```
 */
contract RequestRepository is Authentication {

    struct SaveRequest {
        bytes32 hash;                        // 存证内容哈希
        address creator;                     // 请求创建者
        uint8 voted;                         // 当前已投票数
        bytes ext;                           // 扩展数据（由创建者自定义）
        mapping(address => bool) status;     // 投票人投票状态：true = 已投票
    }

    /// @notice 投票通过所需的最小票数
    uint8 public _threshold;

    /// @notice 哈希 → 存证请求映射
    mapping(bytes32 => SaveRequest) private _saveRequests;

    /// @notice 投票人集合：地址 → 是否为有效投票人
    mapping(address => bool) private _voters;

    // ============================================================
    //  构造函数
    // ============================================================

    /**
     * @notice  初始化投票阈值与投票人集合
     * @dev     投票人数必须至少等于阈值，否则存证请求永远无法通过。
     * @param   threshold   投票通过所需的最小票数
     * @param   voterArray  初始投票人地址数组
     */
    constructor(uint8 threshold, address[] memory voterArray) public {
        require(threshold > 0, "RequestRepository: threshold must be greater than 0");
        _threshold = threshold;

        for (uint i = 0; i < voterArray.length; i++) {
            _voters[voterArray[i]] = true;
        }
    }

    // ============================================================
    //  请求生命周期
    // ============================================================

    /**
     * @notice  创建一个新的存证请求
     * @dev     仅授权地址可调用。同一哈希只能创建一次请求（防止重复）。
     *          存在性校验：利用 mapping 的默认值特性，未被创建的请求 hash 字段为 bytes32(0)。
     * @param   hash    存证内容的哈希值（由 EvidenceController 保证不为 0）
     * @param   owner   请求创建者地址
     * @param   ext     扩展数据，可由业务层自定义格式
     */
    function createSaveRequest(bytes32 hash, address owner, bytes memory ext) public auth {
        require(
            _saveRequests[hash].hash == bytes32(0),
            "RequestRepository: request already exists"
        );

        _saveRequests[hash].hash = hash;
        _saveRequests[hash].creator = owner;
        _saveRequests[hash].ext = ext;
    }

    /**
     * @notice  对存证请求进行投票
     * @dev     仅授权地址可调用。投票人必须在构造函数中指定的投票人集合内。
     *          每人每请求限投一票，重复投票会被拒绝。
     *          投票成功后 voted 字段自增，返回值供 EvidenceController 判断是否达到阈值。
     * @param   hash    存证请求的哈希
     * @param   voter   投票人地址
     * @return  bool    始终返回 true（投票成功）或 revert（失败）
     */
    function voteSaveRequest(bytes32 hash, address voter) public auth returns (bool) {
        require(_voters[voter], "RequestRepository: address is not a voter");
        require(
            _saveRequests[hash].hash == hash,
            "RequestRepository: request not found"
        );

        SaveRequest storage request = _saveRequests[hash];
        require(!request.status[voter], "RequestRepository: voter already voted");

        request.status[voter] = true;
        request.voted++;
        return true;
    }

    /**
     * @notice  查询存证请求的完整数据
     * @dev     返回请求的哈希、创建者、扩展数据、当前票数、投票阈值。
     *          调用方（EvidenceController）通过比较 voted 和 threshold 判断是否通过。
     * @param   hash        请求哈希
     * @return  bytes32     请求哈希
     * @return  creator     创建者地址
     * @return  ext         扩展数据
     * @return  voted       当前已投票数
     * @return  threshold   投票通过阈值
     */
    function getRequestData(bytes32 hash)
        public
        view
        returns (bytes32, address creator, bytes memory ext, uint8 voted, uint8 threshold)
    {
        SaveRequest storage request = _saveRequests[hash];
        require(request.hash == hash, "RequestRepository: request not found");
        return (hash, request.creator, request.ext, request.voted, _threshold);
    }

    /**
     * @notice  删除存证请求
     * @dev     仅授权地址可调用。通常在投票通过、存证写入完毕后由 EvidenceController 调用，
     *          释放链上存储空间。
     * @param   hash  要删除的请求哈希
     */
    function deleteSaveRequest(bytes32 hash) public auth {
        require(
            _saveRequests[hash].hash == hash,
            "RequestRepository: request not found"
        );
        delete _saveRequests[hash];
    }
}