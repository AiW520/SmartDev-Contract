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

/**
 * @title  存证权限基础合约
 * @dev    提供 Owner + 白名单（ACL）双重权限模型，作为存证模块的基类合约。
 *
 *         权限层级：
 *         - onlyOwner：仅合约创建者，可管理白名单
 *         - auth：Owner 或白名单中的地址，可执行核心业务操作
 *
 *         子合约通过 `is Authentication` 继承此合约，获得统一的权限校验能力。
 *         典型使用场景：EvidenceRepository、RequestRepository 均继承自本合约。
 */
contract Authentication {

    /// @notice 合约创建者地址
    address public _owner;

    /// @notice 白名单映射：地址 → 是否授权
    mapping(address => bool) private _acl;

    // ============================================================
    //  事件
    // ============================================================

    /// @notice 白名单地址被授权时触发
    event AddressAuthorized(address indexed addr);

    /// @notice 白名单地址被撤销时触发
    event AddressRevoked(address indexed addr);

    // ============================================================
    //  构造函数
    // ============================================================

    /**
     * @notice 构造函数：设置 msg.sender 为合约 Owner
     */
    constructor() public {
        _owner = msg.sender;
    }

    // ============================================================
    //  权限修饰器
    // ============================================================

    /**
     * @notice 仅 Owner 可调用
     */
    modifier onlyOwner() {
        require(msg.sender == _owner, "Authentication: caller is not the owner");
        _;
    }

    /**
     * @notice Owner 或白名单地址可调用
     * @dev    先检查 Owner（省 gas），再查白名单映射
     */
    modifier auth() {
        require(
            msg.sender == _owner || _acl[msg.sender],
            "Authentication: caller is not authorized"
        );
        _;
    }

    // ============================================================
    //  白名单管理
    // ============================================================

    /**
     * @notice  将地址加入白名单
     * @dev     仅 Owner 可调用。重复授权同一个地址无副作用。
     *          注意：不检查地址是否为零地址，由调用方确保参数有效性。
     * @param   addr  要授权的地址
     */
    function allow(address addr) public onlyOwner {
        require(addr != address(0), "Authentication: cannot authorize zero address");
        _acl[addr] = true;
        emit AddressAuthorized(addr);
    }

    /**
     * @notice  将地址移出白名单
     * @dev     仅 Owner 可调用。若地址本就不在白名单中，操作无副作用。
     * @param   addr  要撤销的地址
     */
    function deny(address addr) public onlyOwner {
        _acl[addr] = false;
        emit AddressRevoked(addr);
    }

    /**
     * @notice  检查地址是否在白名单中
     * @param   addr  要检查的地址
     * @return  bool  true 表示已授权，false 表示未授权
     */
    function isAuthorized(address addr) public view returns (bool) {
        return _acl[addr];
    }
}