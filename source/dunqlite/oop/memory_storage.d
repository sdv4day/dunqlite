/**
 * 内存存储实现
 * 
 * 基于哈希表的内存存储实现，线程安全
 */
module dunqlite.oop.memory_storage;

import dunqlite.oop.error;
import dunqlite.oop.allocator;
import dunqlite.oop.types;
import dunqlite.oop.cursor;
import dunqlite.oop.storage;

import core.sync.mutex;

/**
 * MemoryCursor - 内存存储游标
 * 
 * 遍历MemoryStorage中的所有记录
 */
final class MemoryCursor : Cursor {
    private HashNode* current_;
    
    /**
     * 构造函数
     * 
     * 参数：
     *   storage = 存储对象
     *   first = 第一个节点指针
     */
    this(Storage storage, HashNode* first) {
        super(storage);
        current_ = first;
    }
    
    override bool moveFirst() {
        auto ms = cast(MemoryStorage)storage_;
        current_ = ms.firstNode();
        return current_ !is null;
    }
    
    override bool moveNext() {
        if (current_ is null) return false;
        current_ = current_.next;
        return current_ !is null;
    }
    
    override bool moveLast() {
        auto ms = cast(MemoryStorage)storage_;
        current_ = ms.lastNode();
        return current_ !is null;
    }
    
    override bool movePrevious() {
        if (current_ is null) return false;
        current_ = current_.prev;
        return current_ !is null;
    }
    
    override bool isValid() {
        return current_ !is null;
    }
    
    override const(void)* key() {
        return current_ !is null ? current_.entry.key : null;
    }
    
    override uint keyLength() {
        return current_ !is null ? current_.entry.keyLength : 0;
    }
    
    override const(void)* value() {
        return current_ !is null ? current_.entry.data.ptr : null;
    }
    
    override uint valueLength() {
        return current_ !is null ? cast(uint)current_.entry.data.length : 0;
    }
    
    override int remove() {
        if (current_ is null) return ErrorCode.NOT_FOUND;
        auto ms = cast(MemoryStorage)storage_;
        auto next = current_.next;
        int rc = ms.removeNode(current_);
        current_ = next;
        return rc;
    }
    
    override void reset() {
        moveFirst();
    }
}

/**
 * MemoryStorage - 内存存储
 * 
 * 使用哈希表实现的内存键值存储
 */
class MemoryStorage : Storage {
    private HashNode** buckets_;
    private uint bucketCount_;
    private HashNode* first_;
    private HashNode* last_;
    private Mutex lock_;
    private bool useLock_;
    private bool isResizing_;
    private uint count_;
    
    /**
     * 构造函数
     * 
     * 参数：
     *   alloc = 内存分配器
     */
    this(Allocator alloc = null) {
        super(alloc);
        bucketCount_ = 64;
        auto mem = allocator_.allocateZero(bucketCount_, HashNode.sizeof);
        buckets_ = cast(HashNode**)mem.ptr;
        first_ = null;
        last_ = null;
        lock_ = new Mutex();
        useLock_ = true;
        isResizing_ = false;
        count_ = 0;
    }
    
    ~this() {
        clear();
        if (buckets_ !is null) {
            allocator_.deallocate(buckets_[0..bucketCount_]);
            buckets_ = null;
        }
        destroy(lock_);
    }
    
    private HashNode* findNode(const(void)* key, int keyLen) {
        if (count_ == 0) return null;
        uint hash = HashFunction.compute(key, cast(uint)keyLen);
        uint idx = hash & (bucketCount_ - 1);
        auto node = buckets_[idx];
        while (node !is null) {
            if (node.entry.hash == hash && 
                node.entry.keyLength == cast(uint)keyLen &&
                equalMemory(node.entry.key, key, keyLen)) {
                return node;
            }
            node = node.nextHash;
        }
        return null;
    }
    
    private static bool equalMemory(const(void)* a, const(void)* b, int len) {
        return (cast(const(ubyte)*)a)[0 .. len] == (cast(const(ubyte)*)b)[0 .. len];
    }
    
    private void growBuckets() {
        isResizing_ = true;
        uint newCount = bucketCount_ * 2;
        auto mem = allocator_.allocateZero(newCount, HashNode.sizeof);
        auto newBuckets = cast(HashNode**)mem.ptr;
        if (newBuckets is null) {
            isResizing_ = false;
            return;
        }
        
        auto node = last_;
        for (uint i = 0; i < count_; i++) {
            uint idx = node.entry.hash & (newCount - 1);
            node.nextHash = newBuckets[idx];
            newBuckets[idx] = node;
            node = node.prev;
        }
        
        allocator_.deallocate(buckets_[0..bucketCount_]);
        buckets_ = newBuckets;
        bucketCount_ = newCount;
        
        isResizing_ = false;
    }
    
    override int put(const(void)* key, int keyLen, const(void)* value, long valueLen) {
        lock_.lock();
        scope(exit) lock_.unlock();
        
        auto existing = findNode(key, keyLen);
        
        if (existing !is null) {
            if (existing.entry.data.length == cast(uint)valueLen) {
                Allocator.copyMemory(value[0..cast(size_t)valueLen], existing.entry.data);
            } else {
                existing.entry.free(allocator_);
                existing.entry.data = allocator_.duplicate(value[0..cast(size_t)valueLen]);
                if (existing.entry.data.length == 0) return ErrorCode.NO_MEMORY;
            }
            return ErrorCode.OK;
        }
        
        size_t nodeSize = HashNode.sizeof + keyLen;
        auto nodeMem = allocator_.allocate(nodeSize);
        if (nodeMem.length == 0) return ErrorCode.NO_MEMORY;
        auto node = cast(HashNode*)nodeMem.ptr;
        
        node.allocSize = cast(uint)nodeSize;
        node.entry.key = cast(void*)(cast(ubyte*)node + HashNode.sizeof);
        Allocator.copyMemory(key[0..keyLen], (cast(void*)node.entry.key)[0..keyLen]);
        node.entry.keyLength = cast(uint)keyLen;
        node.entry.hash = HashFunction.compute(key, cast(uint)keyLen);
        
        node.entry.data = allocator_.duplicate(value[0..cast(size_t)valueLen]);
        if (node.entry.data.length == 0) {
            allocator_.deallocate(nodeMem);
            return ErrorCode.NO_MEMORY;
        }
        
        uint idx = node.entry.hash & (bucketCount_ - 1);
        node.nextHash = buckets_[idx];
        buckets_[idx] = node;
        
        node.next = null;
        node.prev = last_;
        if (last_ !is null) {
            last_.next = node;
        } else {
            first_ = node;
        }
        last_ = node;
        
        count_++;
        if (count_ >= bucketCount_ * 4) {
            growBuckets();
        }
        return ErrorCode.OK;
    }
    
    override int get(const(void)* key, int keyLen, void* buf, long* bufLen) {
        lock_.lock();
        scope(exit) lock_.unlock();
        
        auto node = findNode(key, keyLen);
        if (node is null) return ErrorCode.NOT_FOUND;
        
        if (buf !is null && *bufLen >= node.entry.data.length) {
            Allocator.copyMemory(node.entry.data, buf[0..node.entry.data.length]);
        }
        *bufLen = node.entry.data.length;
        return ErrorCode.OK;
    }
    
    override int remove(const(void)* key, int keyLen) {
        lock_.lock();
        scope(exit) lock_.unlock();
        
        auto node = findNode(key, keyLen);
        if (node is null) return ErrorCode.NOT_FOUND;
        return removeNode(node);
    }
    
    package int removeNode(HashNode* node) {
        // 注意：removeNode由remove()调用，锁已持有，不再加锁
        uint idx = node.entry.hash & (bucketCount_ - 1);
        auto p = buckets_[idx];
        HashNode* prevHash = null;
        while (p !is node) {
            prevHash = p;
            p = p.nextHash;
        }
        if (prevHash is null) {
            buckets_[idx] = node.nextHash;
        } else {
            prevHash.nextHash = node.nextHash;
        }
        
        if (node.prev !is null) {
            node.prev.next = node.next;
        } else {
            first_ = node.next;
        }
        if (node.next !is null) {
            node.next.prev = node.prev;
        } else {
            last_ = node.prev;
        }
        
        node.entry.free(allocator_);
        allocator_.deallocate((cast(void*)node)[0..node.allocSize]);
        count_--;
        
        return ErrorCode.OK;
    }
    
    override bool contains(const(void)* key, int keyLen) {
        lock_.lock();
        scope(exit) lock_.unlock();
        
        return findNode(key, keyLen) !is null;
    }
    
    override Cursor createCursor() {
        lock_.lock();
        scope(exit) lock_.unlock();
        
        return new MemoryCursor(this, first_);
    }
    
    override uint count() {
        lock_.lock();
        scope(exit) lock_.unlock();
        return count_;
    }
    
    override void clear() {
        lock_.lock();
        scope(exit) lock_.unlock();
        
        auto node = first_;
        while (node !is null) {
            auto next = node.next;
            node.entry.free(allocator_);
            allocator_.deallocate((cast(void*)node)[0..node.allocSize]);
            node = next;
        }
        first_ = null;
        last_ = null;
        count_ = 0;
        if (buckets_ !is null) {
            buckets_[0..bucketCount_] = null;
        }
    }
    
    HashNode* firstNode() {
        lock_.lock();
        scope(exit) lock_.unlock();
        return first_;
    }
    HashNode* lastNode() {
        lock_.lock();
        scope(exit) lock_.unlock();
        return last_;
    }
}

unittest {
    import std.stdio;
    import std.format : format;

    writeln("[unittest] MemoryStorage put/get/remove/contains");
    {
        auto ms = new MemoryStorage();
        scope(exit) destroy(ms);

        int rc = ms.put("key1".ptr, 4, "val1".ptr, 4);
        assert(rc == ErrorCode.OK);
        assert(ms.count() == 1);
        assert(ms.contains("key1".ptr, 4));
        assert(!ms.contains("key2".ptr, 4));

        long bufLen = 256;
        char[256] buf;
        rc = ms.get("key1".ptr, 4, buf.ptr, &bufLen);
        assert(rc == ErrorCode.OK);
        assert(bufLen == 4);

        rc = ms.remove("key1".ptr, 4);
        assert(rc == ErrorCode.OK);
        assert(ms.count() == 0);
        assert(!ms.contains("key1".ptr, 4));
    }

    writeln("[unittest] MemoryStorage put 覆盖更新");
    {
        auto ms = new MemoryStorage();
        scope(exit) destroy(ms);

        ms.put("key".ptr, 3, "v1".ptr, 2);
        ms.put("key".ptr, 3, "value2_long".ptr, 11);

        long bufLen = 256;
        char[256] buf;
        int rc = ms.get("key".ptr, 3, buf.ptr, &bufLen);
        assert(rc == ErrorCode.OK);
        assert(bufLen == 11);
    }

    writeln("[unittest] MemoryStorage get 查询长度");
    {
        auto ms = new MemoryStorage();
        scope(exit) destroy(ms);

        ms.put("key".ptr, 3, "value".ptr, 5);

        long bufLen = 0;
        int rc = ms.get("key".ptr, 3, null, &bufLen);
        assert(rc == ErrorCode.OK);
        assert(bufLen == 5);
    }

    writeln("[unittest] MemoryStorage get 不存在的键");
    {
        auto ms = new MemoryStorage();
        scope(exit) destroy(ms);

        long bufLen = 256;
        char[256] buf;
        int rc = ms.get("missing".ptr, 7, buf.ptr, &bufLen);
        assert(rc == ErrorCode.NOT_FOUND);
    }

    writeln("[unittest] MemoryStorage remove 不存在的键");
    {
        auto ms = new MemoryStorage();
        scope(exit) destroy(ms);

        int rc = ms.remove("missing".ptr, 7);
        assert(rc == ErrorCode.NOT_FOUND);
    }

    writeln("[unittest] MemoryStorage clear");
    {
        auto ms = new MemoryStorage();
        scope(exit) destroy(ms);

        ms.put("k1".ptr, 2, "v1".ptr, 2);
        ms.put("k2".ptr, 2, "v2".ptr, 2);
        assert(ms.count() == 2);

        ms.clear();
        assert(ms.count() == 0);
        assert(ms.isEmpty());
    }

    writeln("[unittest] MemoryStorage isEmpty/count");
    {
        auto ms = new MemoryStorage();
        scope(exit) destroy(ms);

        assert(ms.isEmpty());
        assert(ms.count() == 0);

        ms.put("k".ptr, 1, "v".ptr, 1);
        assert(!ms.isEmpty());
        assert(ms.count() == 1);
    }

    writeln("[unittest] MemoryStorage createCursor 遍历");
    {
        auto ms = new MemoryStorage();
        scope(exit) destroy(ms);

        ms.put("k1".ptr, 2, "v1".ptr, 2);
        ms.put("k2".ptr, 2, "v2".ptr, 2);
        ms.put("k3".ptr, 2, "v3".ptr, 2);

        auto cursor = ms.createCursor();
        scope(exit) {
            cursor.reset();
            destroy(cursor);
        }

        int count = 0;
        for (cursor.moveFirst(); cursor.isValid(); cursor.moveNext()) {
            assert(cursor.key() !is null);
            assert(cursor.value() !is null);
            assert(cursor.keyLength() > 0);
            assert(cursor.valueLength() > 0);
            count++;
        }
        assert(count == 3);
    }

    writeln("[unittest] MemoryStorage 游标 moveLast/movePrevious");
    {
        auto ms = new MemoryStorage();
        scope(exit) destroy(ms);

        ms.put("k1".ptr, 2, "v1".ptr, 2);
        ms.put("k2".ptr, 2, "v2".ptr, 2);
        ms.put("k3".ptr, 2, "v3".ptr, 2);

        auto cursor = ms.createCursor();
        scope(exit) {
            cursor.reset();
            destroy(cursor);
        }

        assert(cursor.moveLast());
        assert(cursor.isValid());

        int count = 1;
        while (cursor.movePrevious()) {
            count++;
        }
        assert(count == 3);
    }

    writeln("[unittest] MemoryStorage 游标 remove");
    {
        auto ms = new MemoryStorage();
        scope(exit) destroy(ms);

        ms.put("k1".ptr, 2, "v1".ptr, 2);
        ms.put("k2".ptr, 2, "v2".ptr, 2);

        auto cursor = ms.createCursor();
        scope(exit) {
            cursor.reset();
            destroy(cursor);
        }

        cursor.moveFirst();
        int rc = cursor.remove();
        assert(rc == ErrorCode.OK);
        assert(ms.count() == 1);
    }

    writeln("[unittest] MemoryStorage 大量数据插入与扩容");
    {
        auto ms = new MemoryStorage();
        scope(exit) destroy(ms);

        for (int i = 0; i < 500; i++) {
            auto key = format("key_%d", i);
            auto val = format("val_%d", i);
            int rc = ms.put(key.ptr, cast(int)key.length, val.ptr, cast(int)val.length);
            assert(rc == ErrorCode.OK);
        }
        assert(ms.count() == 500);

        for (int i = 0; i < 500; i++) {
            auto key = format("key_%d", i);
            assert(ms.contains(key.ptr, cast(int)key.length));
        }
    }
}
