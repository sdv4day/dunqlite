/**
 * 基础类型定义
 * 
 * 提供键值存储的基础数据结构和工具类
 */
module dunqlite.oop.types;

import dunqlite.oop.allocator;

/**
 * HashFunction - 哈希函数工具类
 * 
 * 提供字符串和二进制数据的哈希计算
 * 使用djb2算法（简单高效）
 */
final class HashFunction {
    /**
     * 计算哈希值
     * 
     * 参数：
     *   data = 数据指针
     *   length = 数据长度
     * 
     * 返回：
     *   32位哈希值
     */
    static uint compute(const(void)* data, uint length) {
        auto bytes = cast(const(ubyte)*)data;
        uint hash = 5381;
        for (uint i = 0; i < length; i++) {
            hash = hash * 33 + bytes[i];
        }
        return hash;
    }
}

/**
 * KvEntry - 键值条目
 * 
 * 存储单个键值对的数据结构
 */
struct KvEntry {
    const(void)* key;    /// 键指针
    uint keyLength;      /// 键长度
    void[] data;         /// 值数据
    uint hash;           /// 键的哈希值
    
    /**
     * 释放值数据
     * 
     * 参数：
     *   alloc = 内存分配器
     */
    void free(Allocator alloc) {
        if (data.length > 0) {
            alloc.deallocate(data);
            data = null;
        }
    }
}

/**
 * HashNode - 哈希节点
 * 
 * 哈希表中的节点结构，用于内存存储
 */
struct HashNode {
    KvEntry entry;        /// 键值条目
    HashNode* next;       /// 双向链表下一个节点
    HashNode* prev;       /// 双向链表前一个节点
    HashNode* nextHash;   /// 哈希桶中的下一个节点
    uint allocSize;       /// 分配的总大小（用于正确释放）
}
