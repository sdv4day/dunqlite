/**
 * 数据库模块
 * 
 * 提供数据库的主要接口，组合Storage和Transaction
 * 支持泛型put/get/del/find接口
 * 支持多进程并发访问（跨进程文件锁）
 */
module dunqlite.oop.database;

import dunqlite.oop.error;
import dunqlite.oop.allocator;
import dunqlite.oop.storage;
import dunqlite.oop.memory_storage;
import dunqlite.oop.file_storage;
import dunqlite.oop.transaction;
import dunqlite.oop.cursor;
import dunqlite.oop.slice;
import dunqlite.oop.shared_lock;

import std.traits;
import std.conv : text;
import core.sync.mutex;

/**
 * Database - 数据库类
 * 
 * 组合Storage和Transaction，提供统一的数据库操作接口
 */
class Database {
    /**
     * 数据库标志枚举
     */
    private enum Flag {
        Open = 0x01,      /// 已打开
        InMemory = 0x02,  /// 内存模式
        ReadOnly = 0x04   /// 只读模式
    }
    
    private Storage storage_;
    private Transaction transaction_;
    private Allocator allocator_;
    private SharedFileLock fileLock_;
    private Mutex dbLock_;
    private int flags_;
    private string dbPath_;
    
    /**
     * 构造函数
     * 
     * 参数：
     *   alloc = 内存分配器（null则使用全局分配器）
     */
    this(Allocator alloc = null) {
        allocator_ = alloc ? alloc : GlobalAllocator.instance();
        storage_ = null;
        transaction_ = null;
        fileLock_ = null;
        dbLock_ = new Mutex();
        flags_ = 0;
        dbPath_ = null;
    }
    
    /**
     * 析构函数
     * 
     * 自动关闭数据库
     */
    ~this() {
        close();
    }
    
    /**
     * 打开数据库
     * 
     * 参数：
     *   filename = 数据库路径（null则纯内存模式）
     *   inMemory = 是否使用内存模式
     *   readOnly = 是否只读模式
     * 
     * 返回：
     *   错误码
     * 
     * 多进程说明：
     *   - 当filename非null时，自动创建跨进程文件锁
     *   - 写操作自动获取排他锁
     *   - 读操作自动获取共享锁
     *   - 多个进程可同时读取，写入时排他
     */
    int open(const(char)* filename = null, bool inMemory = true, bool readOnly = false) {
        if (isOpen()) return ErrorCode.OK;
        
        if (inMemory) {
            storage_ = new MemoryStorage(allocator_);
        } else {
            if (filename is null) {
                return ErrorCode.INVALID;
            }
            storage_ = new FileStorage(text(filename), allocator_);
        }
        
        // 多进程文件锁
        if (filename !is null) {
            dbPath_ = text(filename);
            auto lockPath = dbPath_ ~ ".lock";
            fileLock_ = new SharedFileLock(lockPath);
            
            if (readOnly) {
                if (!fileLock_.lockRead()) {
                    return ErrorCode.IO_ERROR;
                }
                flags_ |= Flag.ReadOnly;
            } else {
                if (!fileLock_.tryLockWrite()) {
                    // 写锁失败，尝试读锁
                    if (!fileLock_.lockRead()) {
                        return ErrorCode.IO_ERROR;
                    }
                    flags_ |= Flag.ReadOnly;
                }
            }
        }
        
        transaction_ = new Transaction(storage_);
        flags_ |= Flag.Open;
        if (inMemory) flags_ |= Flag.InMemory;
        
        return ErrorCode.OK;
    }
    
    /**
     * 关闭数据库
     * 
     * 返回：
     *   错误码
     */
    int close() {
        if (!isOpen()) return ErrorCode.OK;
        
        // 文件存储需要刷盘
        if (storage_ !is null) {
            auto fileStorage = cast(FileStorage) storage_;
            if (fileStorage !is null) {
                fileStorage.sync();  // 先刷盘
            }
        }
        
        if (storage_ !is null) {
            storage_.clear();
            destroy(storage_);
            storage_ = null;
        }
        
        if (transaction_ !is null) {
            destroy(transaction_);
            transaction_ = null;
        }
        
        if (fileLock_ !is null) {
            fileLock_.unlock();
            destroy(fileLock_);
            fileLock_ = null;
        }
        
        flags_ = 0;
        dbPath_ = null;
        return ErrorCode.OK;
    }
    
    /**
     * 存储键值对
     * 
     * 参数：
     *   key = 键指针
     *   keyLen = 键长度
     *   value = 值指针
     *   valueLen = 值长度
     * 
     * 返回：
     *   错误码
     */
    int put(const(void)* key, int keyLen, const(void)* value, long valueLen) {
        if (!isOpen()) return ErrorCode.INVALID;
        return storage_.put(key, keyLen, value, valueLen);
    }
    
    /**
     * 获取值
     * 
     * 参数：
     *   key = 键指针
     *   keyLen = 键长度
     *   buf = 接收缓冲区
     *   bufLen = 输入为缓冲区大小，输出为实际值长度
     * 
     * 返回：
     *   错误码
     */
    int get(const(void)* key, int keyLen, void* buf, long* bufLen) {
        if (!isOpen()) return ErrorCode.INVALID;
        return storage_.get(key, keyLen, buf, bufLen);
    }
    
    /**
     * 删除键值对
     * 
     * 参数：
     *   key = 键指针
     *   keyLen = 键长度
     * 
     * 返回：
     *   错误码
     */
    int remove(const(void)* key, int keyLen) {
        if (!isOpen()) return ErrorCode.INVALID;
        return storage_.remove(key, keyLen);
    }
    
    /**
     * 检查键是否存在
     * 
     * 参数：
     *   key = 键指针
     *   keyLen = 键长度
     * 
     * 返回：
     *   是否存在
     */
    bool contains(const(void)* key, int keyLen) {
        if (!isOpen()) return false;
        return storage_.contains(key, keyLen);
    }
    
    /**
     * 开始事务
     * 
     * 返回：
     *   错误码
     */
    int beginTransaction() {
        if (!isOpen()) return ErrorCode.INVALID;
        return transaction_.begin();
    }
    
    /**
     * 提交事务
     * 
     * 返回：
     *   错误码
     */
    int commit() {
        if (!isOpen()) return ErrorCode.INVALID;
        return transaction_.commit();
    }
    
    /**
     * 回滚事务
     * 
     * 返回：
     *   错误码
     */
    int rollback() {
        if (!isOpen()) return ErrorCode.INVALID;
        return transaction_.rollback();
    }
    
    /**
     * 创建游标
     * 
     * 返回：
     *   游标实例
     */
    Cursor createCursor() {
        if (!isOpen()) return null;
        return storage_.createCursor();
    }
    
    /**
     * 检查数据库是否已打开
     * 
     * 返回：
     *   是否已打开
     */
    bool isOpen() { return (flags_ & Flag.Open) != 0; }
    
    /**
     * 检查是否为内存模式
     * 
     * 返回：
     *   是否为内存模式
     */
    bool isInMemory() { return (flags_ & Flag.InMemory) != 0; }
    
    /**
     * 检查是否为只读模式
     * 
     * 返回：
     *   是否为只读模式
     */
    bool isReadOnly() { return (flags_ & Flag.ReadOnly) != 0; }
    
    /**
     * 获取数据库路径
     * 
     * 返回：
     *   数据库路径（null为纯内存模式）
     */
    string path() { return dbPath_; }
    
    /**
     * 获取记录数量
     * 
     * 返回：
     *   记录数
     */
    uint count() { return storage_ !is null ? storage_.count() : 0; }
    
    /**
     * 检查是否为空
     * 
     * 返回：
     *   是否为空
     */
    bool isEmpty() { return storage_ !is null ? storage_.isEmpty() : true; }
    
    /**
     * 获取存储对象
     * 
     * 返回：
     *   Storage实例
     */
    Storage storage() { return storage_; }
    
    /**
     * 获取事务对象
     * 
     * 返回：
     *   Transaction实例
     */
    Transaction transaction() { return transaction_; }
    
    /**
     * 获取内存分配器
     * 
     * 返回：
     *   Allocator实例
     */
    Allocator allocator() { return allocator_; }
    
    // ========================================================================
    // 泛型接口（参考 dleveldb）
    // ========================================================================
    
    /**
     * 写入键值对（泛型）
     * 
     * 支持任意可序列化为 Slice 的类型
     * 
     * 示例：
     *   db.put("key", "value");
     *   db.put("key", 42);
     *   db.put(Slice("key"), Slice.Ref(3.14));
     */
    int put(K, V)(in K key, in V value) {
        dbLock_.lock();
        scope(exit) dbLock_.unlock();
        
        if (!isOpen()) return ErrorCode.INVALID;
        auto keySlice = toSliceKey(key);
        auto valSlice = toSlice(value);
        return storage_.put(keySlice.data(), cast(int)keySlice.size(), 
                           valSlice.data(), cast(long)valSlice.size());
    }
    
    /**
     * 读取键值（泛型）
     * 
     * 返回：是否找到
     * 
     * 示例：
     *   string val;
     *   if (db.get("key", val)) { ... }
     */
    bool get(K, V)(in K key, out V value)
        if (!is(V == interface))
    {
        dbLock_.lock();
        scope(exit) dbLock_.unlock();
        
        if (!isOpen()) return false;
        auto keySlice = toSliceKey(key);
        
        // 先查询长度
        long bufLen = 0;
        int rc = storage_.get(keySlice.data(), cast(int)keySlice.size(), 
                             null, &bufLen);
        if (rc != ErrorCode.OK) return false;
        
        // 分配足够的缓冲区
        auto buf = new ubyte[cast(size_t)bufLen];
        long actualLen = bufLen;
        rc = storage_.get(keySlice.data(), cast(int)keySlice.size(), 
                         buf.ptr, &actualLen);
        if (rc != ErrorCode.OK) return false;
        
        auto resultSlice = Slice(buf.ptr, cast(size_t)actualLen);
        value = fromSlice!V(resultSlice);
        return true;
    }
    
    /**
     * 删除键（泛型）
     */
    int del(K)(in K key) {
        dbLock_.lock();
        scope(exit) dbLock_.unlock();
        
        if (!isOpen()) return ErrorCode.INVALID;
        auto keySlice = toSliceKey(key);
        return storage_.remove(keySlice.data(), cast(int)keySlice.size());
    }
    
    /**
     * 查找键值，不存在返回默认值（泛型）
     */
    V find(K, V)(in K key, V def) {
        V value;
        if (get(key, value)) {
            return value;
        }
        return def;
    }
    
    /**
     * 获取键值的 Slice（不拷贝）
     * 
     * 注意：返回的 Slice 引用临时内存，调用者应立即使用
     */
    Slice getSlice(K)(in K key) {
        dbLock_.lock();
        scope(exit) dbLock_.unlock();
        
        if (!isOpen()) return Slice();
        
        auto keySlice = toSliceKey(key);
        
        // 先查询长度
        long bufLen = 0;
        int rc = storage_.get(keySlice.data(), cast(int)keySlice.size(), 
                             null, &bufLen);
        if (rc != ErrorCode.OK) return Slice();
        
        // 分配足够的缓冲区（GC管理，Slice安全引用）
        auto buf = new ubyte[cast(size_t)bufLen];
        long actualLen = bufLen;
        rc = storage_.get(keySlice.data(), cast(int)keySlice.size(), 
                         buf.ptr, &actualLen);
        if (rc != ErrorCode.OK) return Slice();
        
        return Slice(buf.ptr, cast(size_t)actualLen);
    }
    
    /// 重载 db[key]
    Slice opIndex(K)(K key) {
        return getSlice(key);
    }
    
    /// 重载 db[key] = val
    int opIndexAssign(K, V)(V val, K key) {
        return put(key, val);
    }
    
private:
    /// 将任意类型转换为 Slice（用于 key）
    static Slice toSliceKey(T)(in T val) {
        static if (is(T == Slice)) {
            return val;
        }
        else static if (isSomeString!T || isDynamicArray!T || isPointer!T) {
            return toSlice(val);
        }
        else {
            // 基本类型和POD结构体：堆分配避免栈悬空引用
            auto buf = new ubyte[T.sizeof];
            (cast(ubyte*)buf.ptr)[0 .. T.sizeof] = (cast(const(ubyte)*)&val)[0 .. T.sizeof];
            return Slice(cast(const(void*)) buf.ptr, T.sizeof);
        }
    }
    
    /// 将任意类型转换为 Slice（用于 value）
    static Slice toSlice(T)(in T val) {
        static if (is(T == Slice)) {
            return val;
        }
        else static if (isSomeString!T) {
            return Slice(val);
        }
        else static if (isDynamicArray!T) {
            import std.range.primitives : ElementEncodingType;
            static if (is(ElementEncodingType!T == ubyte) || is(ElementEncodingType!T == const(ubyte))) {
                return Slice(val);
            }
            else static if (is(ElementEncodingType!T == char) || is(ElementEncodingType!T == const(char))) {
                return Slice(val);
            }
            else {
                return Slice(cast(const(void*)) val.ptr, val.length * ElementEncodingType!T.sizeof);
            }
        }
        else static if (isPointer!T) {
            return Slice(cast(const(void*)) val, T.sizeof);
        }
        else {
            // 基本类型和POD结构体：堆分配避免TLS竞争和栈悬空
            auto buf = new ubyte[T.sizeof];
            (cast(ubyte*)buf.ptr)[0 .. T.sizeof] = (cast(const(ubyte)*)&val)[0 .. T.sizeof];
            return Slice(cast(const(void*)) buf.ptr, T.sizeof);
        }
    }
    
    /// 从 Slice 转换为目标类型
    static V fromSlice(V)(Slice s) {
        static if (isSomeString!V) {
            return s.asString().idup;
        }
        else static if (isDynamicArray!V && !is(V == class)) {
            import std.range.primitives : ElementEncodingType;
            auto result = new V(s.length / ElementEncodingType!V.sizeof);
            result[] = (cast(ElementEncodingType!V[]) s.asBytes())[0 .. result.length];
            return result;
        }
        else {
            V result;
            const(ubyte)* src = s.data();
            (cast(ubyte*)&result)[0 .. V.sizeof] = src[0 .. V.sizeof];
            return result;
        }
    }
}
