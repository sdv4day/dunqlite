/**
 * 基础类型定义
 * 
 * 提供键值存储的基础数据结构和工具类
 */
module dunqlite.oop.types;

import dunqlite.oop.allocator;

/**
 * HashFunction - 哈希函数工具
 * 
 * 提供字符串和二进制数据的哈希计算
 * 使用djb2算法（简单高效）
 */
struct HashFunction {
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

unittest {
    import std.stdio;

    writeln("[unittest] HashFunction.compute");
    {
        auto h1 = HashFunction.compute("hello".ptr, 5);
        auto h2 = HashFunction.compute("hello".ptr, 5);
        assert(h1 == h2);

        auto h3 = HashFunction.compute("world".ptr, 5);
        assert(h1 != h3);

        auto h4 = HashFunction.compute("hello".ptr, 3);
        assert(h1 != h4);

        auto h5 = HashFunction.compute(null, 0);
        assert(h5 == 5381);
    }

    writeln("[unittest] KvEntry.free");
    {
        auto alloc = GlobalAllocator.instance();
        KvEntry entry;
        entry.key = "testkey".ptr;
        entry.keyLength = 7;
        entry.data = alloc.duplicate(cast(const(void)[])"testvalue");
        entry.hash = 0;

        assert(entry.data.length > 0);
        entry.free(alloc);
        assert(entry.data.length == 0);

        entry.free(alloc);
    }

    writeln("[unittest] HashNode 结构");
    {
        HashNode node;
        assert(node.next is null);
        assert(node.prev is null);
        assert(node.nextHash is null);
        assert(node.allocSize == 0);
        assert(node.entry.key is null);
        assert(node.entry.data.length == 0);
    }
}
