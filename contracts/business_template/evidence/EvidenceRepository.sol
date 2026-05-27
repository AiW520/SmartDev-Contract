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

import "./Authentication.sol";

/**
 * @title  存证数据仓库
 * @dev    负责存证数据（哈希、所有者、时间戳）的写入和查询。
 *         继承 Authentication 合约，仅授权地址（Owner 或白名单）可写入。
 *
 *         数据模型：
 *         - hash（bytes32）：存证内容的哈希值，唯一标识一条存证记录
 *         - owner（address）：存证的创建者地址
 *         - timestamp（uint）：存证上链的时间戳（block.timestamp）
 *
 *         注意：本合约本身不实现业务判断逻辑（如投票阈值），仅提供数据存取接口。
 *         业务编排由 EvidenceController 完成。
 */
contract EvidenceRepository is Authentication {

    struct EvidenceData {
        bytes32 hash;       // 存证哈希；同时用作存在性标记（未存证时默认为 bytes32(0)）
        address owner;      // 存证所有者
        uint timestamp;    // 存证时间戳
    }

    /// @notice 哈希 → 存证数据映射
    mapping(bytes32 => EvidenceData) private _evidences;

    // ============================================================
    //  数据存取
    // ============================================================

    /**
     * @notice  写入一条存证记录
     * @dev     仅授权地址可调用。对已存在的哈希重复写入会覆盖原有记录（幂等操作）。
     *          数据来源：由 EvidenceController 在投票通过后调用，hash 来自请求，owner 为请求创建者，
     *          timestamp 使用当前区块时间戳。
     * @param   hash      存证内容的哈希值
     * @param   owner     存证所有者地址
     * @param   timestamp 存证时间戳
     */
    function setData(bytes32 hash, address owner, uint timestamp) public auth {
        _evidences[hash].hash = hash;
        _evidences[hash].owner = owner;
        _evidences[hash].timestamp = timestamp;
    }

    /**
     * @notice  查询一条存证记录
     * @dev     通过哈希定位记录。由于 EvidenceController 在写入前保证 hash != 0，
     *          可用 `evidence.hash == hash` 作为存在性校验（不存在的记录 hash 为 bytes32(0)，
     *          必然不等于传入的非零 hash）。
     * @param   hash      要查询的存证哈希
     * @return  bytes32   存证哈希值
     * @return  address   存证所有者地址
     * @return  uint      存证时间戳
     */
    function getData(bytes32 hash)
        public
        view
        returns (bytes32, address, uint)
    {
        EvidenceData storage evidence = _evidences[hash];
        require(evidence.hash == hash, "EvidenceRepository: evidence not found");
        return (evidence.hash, evidence.owner, evidence.timestamp);
    }
}