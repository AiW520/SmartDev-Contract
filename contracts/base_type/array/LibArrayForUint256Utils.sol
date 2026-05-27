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

import "./LibSafeMathForUint256Utils.sol";

/**
 * @title  Uint256 动态数组工具库
 * @dev    提供对 uint256[] storage 数组的常用操作，包括查找、排序、去重、反转等。
 *         所有函数均操作 storage 引用，直接修改链上数据，无需返回新数组。
 *         注意：部分函数（如 distinct、removeByIndex）会修改数组长度，调用时需确保
 *         调用者合约有足够的 gas 预算。时间复杂度标注在对应函数的 @dev 中。
 */
library LibArrayForUint256Utils {

    // ============================================================
    //  查找操作
    // ============================================================

    /**
     * @notice  二分查找：在升序排列的数组中定位目标值
     * @dev     要求数组已按升序排列，否则结果无意义。时间复杂度 O(log n)。
     *          使用 LibSafeMathForUint256Utils.average 计算中间索引，防止加法溢出。
     * @param   array  升序排列的 uint256 数组
     * @param   key    要查找的目标值
     * @return  bool   找到返回 true，否则 false
     * @return  uint   匹配元素的下标索引；未找到时返回 0（需结合 bool 返回值判断有效性）
     */
    function binarySearch(uint256[] storage array, uint256 key)
        internal
        view
        returns (bool, uint)
    {
        if (array.length == 0) {
            return (false, 0);
        }

        uint256 low = 0;
        uint256 high = array.length - 1;

        while (low <= high) {
            uint256 mid = LibSafeMathForUint256Utils.average(low, high);
            if (array[mid] == key) {
                return (true, mid);
            } else if (array[mid] > key) {
                high = mid - 1;
            } else {
                low = mid + 1;
            }
        }

        return (false, 0);
    }

    /**
     * @notice  线性查找：返回目标值在数组中首次出现的索引
     * @dev     从头遍历直到匹配或末尾。时间复杂度 O(n)。
     *          不要求数组有序，适用于无序数组的查找场景。
     * @param   array  目标数组
     * @param   key    要查找的值
     * @return  bool   找到返回 true，否则 false
     * @return  uint256 首次出现的索引；未找到返回 0（需结合 bool 判断）
     */
    function firstIndexOf(uint256[] storage array, uint256 key)
        internal
        view
        returns (bool, uint256)
    {
        if (array.length == 0) {
            return (false, 0);
        }

        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == key) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    // ============================================================
    //  比较与变换操作
    // ============================================================

    /**
     * @notice  反转数组：将元素顺序完全颠倒
     * @dev     原地反转，不创建新数组。时间复杂度 O(n/2)。
     *          使用首尾双指针交换，对长度为奇数的数组中间元素保持不变。
     * @param   array  要反转的数组
     */
    function reverse(uint256[] storage array) internal {
        uint256 temp;
        for (uint i = 0; i < array.length / 2; i++) {
            temp = array[i];
            array[i] = array[array.length - 1 - i];
            array[array.length - 1 - i] = temp;
        }
    }

    /**
     * @notice  判断两个数组是否完全相等
     * @dev     先比较长度，再逐元素比较。时间复杂度 O(n)。
     *          利用长度快速短路：长度不等时立即返回 false，无需遍历。
     * @param   a  第一个数组
     * @param   b  第二个数组
     * @return  bool  长度相同且每个对应元素相等则返回 true，否则 false
     */
    function equals(uint256[] storage a, uint256[] storage b)
        internal
        view
        returns (bool)
    {
        if (a.length != b.length) {
            return false;
        }
        for (uint256 i = 0; i < a.length; i++) {
            if (a[i] != b[i]) {
                return false;
            }
        }
        return true;
    }

    // ============================================================
    //  增删操作
    // ============================================================

    /**
     * @notice  按索引移除元素，后续元素自动前移
     * @dev     通过循环将 index 之后的元素逐个向前移动，最后缩短数组长度。
     *          时间复杂度 O(n)。注意：数组元素顺序会改变（类似 splice 效果）。
     * @param   array  目标数组
     * @param   index  要移除的元素索引（从 0 开始）
     */
    function removeByIndex(uint256[] storage array, uint index) internal {
        require(index < array.length, "LibArrayForUint256Utils: index out of bounds");

        // 将 index 之后的元素依次前移一位
        for (uint i = index; i < array.length - 1; i++) {
            array[i] = array[i + 1];
        }

        // 缩短数组长度，丢弃末尾已移动的冗余元素
        array.length--;
    }

    /**
     * @notice  按值移除元素（仅移除首次匹配项）
     * @dev     内部复用 firstIndexOf 查找，再调用 removeByIndex 执行删除。
     *          时间复杂度 O(n)。若值不存在则数组保持不变。
     * @param   array  目标数组
     * @param   value  要移除的值
     */
    function removeByValue(uint256[] storage array, uint256 value) internal {
        uint index;
        bool isIn;
        (isIn, index) = firstIndexOf(array, value);
        if (isIn) {
            removeByIndex(array, index);
        }
    }

    /**
     * @notice  向数组末尾追加元素，已存在则跳过（去重添加）
     * @dev     先通过 firstIndexOf 检查是否存在，不存在才 push。
     *          时间复杂度 O(n)。适用于需要维护无重复集合的场景。
     * @param   array  目标数组
     * @param   value  要添加的值
     */
    function addValue(uint256[] storage array, uint256 value) internal {
        uint index;
        bool isIn;
        (isIn, index) = firstIndexOf(array, value);
        if (!isIn) {
            array.push(value);
        }
    }

    /**
     * @notice  将数组 b 的所有元素追加到数组 a 末尾
     * @dev     直接逐元素 push，不进行去重。时间复杂度 O(m)，m = b.length。
     *          若 b 为空数组则无操作。
     * @param   a  被扩展的目标数组
     * @param   b  提供追加元素的源数组
     */
    function extend(uint256[] storage a, uint256[] storage b) internal {
        for (uint i = 0; i < b.length; i++) {
            a.push(b[i]);
        }
    }

    /**
     * @notice  数组去重：保留每个值的首次出现，移除后续重复项
     * @dev     原地去重，使用双循环实现（外层遍历每个元素，内层查找后续重复项并删除）。
     *          时间复杂度 O(n²)，每条链上操作有单独的 gas 开销，大数组慎用。
     *          算法保证：去重后元素之间的相对顺序不变（保留首次出现的位置）。
     * @param   array  要去重的数组
     * @return  length  去重后的数组长度
     */
    function distinct(uint256[] storage array) internal returns (uint256 length) {
        bool contains;
        uint index;

        for (uint i = 0; i < array.length; i++) {
            contains = false;
            index = 0;

            // 在 i 之后查找与 array[i] 相同的重复元素
            uint j = i + 1;
            for (; j < array.length; j++) {
                if (array[j] == array[i]) {
                    contains = true;
                    index = j;       // 记录重复元素的位置
                    break;
                }
            }

            if (contains) {
                // 将重复元素（index 处）移除，后续元素前移
                for (j = index; j < array.length - 1; j++) {
                    array[j] = array[j + 1];
                }
                array.length--;
                i--;    // 回退 i，因为当前元素之后的所有元素都向前移动了一位
            }
        }

        length = array.length;
    }

    // ============================================================
    //  排序操作
    // ============================================================

    /**
     * @notice  快速排序（入口）：对数组进行原地升序排列
     * @dev     
     * 采用 Hoare 分区方案的快速排序，平均时间复杂度 O(n log n)，最坏 O(n²)。
     * 选择末尾元素作为 pivot，通过左右指针交换实现分区。
     *         包含空数组安全保护：`end == uint256(-1)` 捕获 array.length == 0 时
     *         `array.length - 1` 下溢的情况，直接返回避免异常。
     * @param   array  要排序的数组
     */
    function qsort(uint256[] storage array) internal {
        qsort(array, 0, array.length - 1);
    }

    /**
     * @notice  快速排序（递归）：对数组 [begin, end] 闭区间进行分区排序
     * @dev     私有递归实现，外部应通过无参重载 qsort(array) 调用。
     *          pivot 选择策略：始终取 `array[end]`（末尾元素）。
     *          `end == uint256(-1)` 用于在 array.length == 0 时安全终止递归。
     * @param   array  要排序的数组
     * @param   begin  排序区间的起始索引
     * @param   end    排序区间的结束索引
     */
    function qsort(uint256[] storage array, uint256 begin, uint256 end) private {
        // 区间无效或数组为空时终止递归
        if (begin >= end || end == uint256(-1)) return;

        uint256 pivot = array[end];
        uint256 store = begin;

        // 分区：将小于 pivot 的元素交换到左侧
        for (uint256 i = begin; i < end; i++) {
            if (array[i] < pivot) {
                uint256 tmp = array[i];
                array[i] = array[store];
                array[store] = tmp;
                store++;
            }
        }

        // 将 pivot 放到正确位置
        array[end] = array[store];
        array[store] = pivot;

        // 递归排序左右子区间
        qsort(array, begin, store - 1);
        qsort(array, store + 1, end);
    }

    // ============================================================
    //  统计操作
    // ============================================================

    /**
     * @notice  查找数组中的最大值及其索引
     * @dev     线性扫描，时间复杂度 O(n)。
     *          若存在多个相同最大值，返回首次出现的索引。
     * @param   array     目标数组
     * @return  maxValue  数组中的最大值
     * @return  maxIndex  最大值首次出现的索引
     */
    function max(uint256[] storage array)
        internal
        view
        returns (uint256 maxValue, uint256 maxIndex)
    {
        require(array.length > 0, "LibArrayForUint256Utils: empty array");
        maxValue = array[0];
        maxIndex = 0;

        for (uint256 i = 1; i < array.length; i++) {
            if (array[i] > maxValue) {
                maxValue = array[i];
                maxIndex = i;
            }
        }
    }

    /**
     * @notice  查找数组中的最小值及其索引
     * @dev     线性扫描，时间复杂度 O(n)。
     *          若存在多个相同最小值，返回首次出现的索引。
     * @param   array     目标数组
     * @return  minValue  数组中的最小值
     * @return  minIndex  最小值首次出现的索引
     */
    function min(uint256[] storage array)
        internal
        view
        returns (uint256 minValue, uint256 minIndex)
    {
        require(array.length > 0, "LibArrayForUint256Utils: empty array");
        minValue = array[0];
        minIndex = 0;

        for (uint256 i = 1; i < array.length; i++) {
            if (array[i] < minValue) {
                minValue = array[i];
                minIndex = i;
            }
        }
    }

}