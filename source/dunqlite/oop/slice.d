/**
 * 零拷贝字节引用
 * 
 * 类似 LevelDB 的 Slice，不拥有数据，仅引用外部内存
 * 支持泛型类型转换和安全引用创建
 */
module dunqlite.oop.slice;

import std.traits;
import std.conv : to;

/**
 * Slice - 零拷贝字节引用结构体
 * 
 * 不拥有数据，仅引用外部内存
 * 支持泛型类型转换 as!T 和安全引用创建 Ref!T
 */
struct Slice {
    const(ubyte)* data_ = null;
    size_t size_ = 0;
    
    /**
     * 从字节数组构造
     */
    this(const(ubyte)[] arr) pure nothrow @trusted @nogc {
        data_ = arr.ptr;
        size_ = arr.length;
    }
    
    /**
     * 从字符串构造
     */
    this(const(char)[] str) pure nothrow @trusted @nogc {
        data_ = cast(const(ubyte)*) str.ptr;
        size_ = str.length;
    }
    
    /**
     * 从指针和长度构造
     */
    this(const void* ptr, size_t len) pure nothrow @safe @nogc {
        data_ = cast(const(ubyte)*) ptr;
        size_ = len;
    }
    
    /// 获取数据指针
    const(ubyte)* data() const pure nothrow @safe @nogc { return data_; }
    
    /// 获取数据长度
    size_t size() const pure nothrow @safe @nogc { return size_; }
    
    /// 别名：length
    alias length = size;
    
    /// 是否为空
    bool empty() const pure nothrow @safe @nogc { return size_ == 0; }
    
    /// 是否有效（非空）
    bool ok() const pure nothrow @safe @nogc { return size_ > 0; }
    
    /// 清空
    void clear() pure nothrow @safe @nogc {
        data_ = null;
        size_ = 0;
    }
    
    /// 转为ubyte数组视图
    const(ubyte)[] asBytes() const pure nothrow @trusted @nogc {
        return data_[0 .. size_];
    }
    
    /// 转为char数组视图
    const(char)[] asString() const pure nothrow @trusted @nogc {
        return (cast(const(char)*) data_)[0 .. size_];
    }
    
    /**
     * 泛型类型转换：将 Slice 数据解释为类型 T
     * 
     * 支持类型：
     *   - 字符串：as!string → 复制为 string
     *   - 基本类型：as!int / as!long / as!double 等
     *   - POD 结构体：as!Point 等
     *   - 动态数组：as!(int[]) 等
     */
    @property
    inout(T) as(T)() inout
        if (!isPointer!T && __traits(compiles, *(cast(inout(T*)) data_)))
    {
        static if (isSomeString!T) {
            return (cast(inout(T)) (cast(inout(char)*) data_)[0 .. size_]).idup;
        }
        else static if (isDynamicArray!T && !is(T == class)) {
            import std.range.primitives : ElementEncodingType;
            return cast(inout(T)) (cast(inout(ElementEncodingType!T)*) data_)[0 .. size_ / ElementEncodingType!T.sizeof];
        }
        else {
            return *(cast(inout(T*)) data_);
        }
    }
    
    /// 别名：to 是 as 的别名
    alias to = as;
    
    /**
     * 为基本类型常量创建安全引用 Slice
     * 
     * 数据存储在 TLS 缓冲区中，Slice 仅引用
     * ⚠ 生命周期陷阱：返回的Slice引用TLS缓冲区，
     *   下次对同一类型T调用Ref()会覆盖前值
     * 
     * 示例：
     *   auto s = Slice.Ref(42);  // 创建 int 值 42 的 Slice
     */
    static Slice Ref(T)(T value)
        if (isBasicType!T || isPODStruct!T)
    {
        import std.traits : Unqual;
        static Unqual!T storage;
        storage = cast(Unqual!T) value;
        return Slice(cast(const(void*)) &storage, Unqual!T.sizeof);
    }
    
    /// 比较两个Slice
    int opCmp(Slice rhs) const nothrow @nogc {
        import std.algorithm.comparison : cmp;
        return cmp(data_[0 .. size_], rhs.data_[0 .. rhs.size_]);
    }
    
    /// 相等比较
    bool opEquals(Slice rhs) const nothrow @nogc {
        if (size_ != rhs.size_)
            return false;
        if (size_ == 0)
            return true;
        return data_[0 .. size_] == rhs.data_[0 .. size_];
    }
    
    /// 哈希值
    size_t toHash() const nothrow @nogc {
        if (size_ == 0) return 0;
        size_t hash = 5381;
        for (size_t i = 0; i < size_; i++) {
            hash = hash * 33 + data_[i];
        }
        return hash;
    }
    
    /// 前缀判断
    bool startsWith(Slice prefix) const nothrow @nogc {
        return (size_ >= prefix.size_) && (Slice(data_[0 .. prefix.size_]) == prefix);
    }
    
    /// 后缀判断
    bool endsWith(Slice suffix) const nothrow @nogc {
        return (size_ >= suffix.size_) &&
            (Slice(data_[size_ - suffix.size_ .. size_]) == suffix);
    }
    
    /// 去除前缀
    Slice removePrefix(size_t n) const pure nothrow @trusted @nogc
        in (n <= size_)
    {
        return Slice(data_ + n, size_ - n);
    }
    
    /// 字符串表示（用于调试）
    string toString() const {
        import std.format : format;
        if (size_ <= 64) {
            return asString().idup;
        }
        return format("%s...(truncated %d bytes)", asString()[0 .. 64].idup, size_ - 64);
    }
}

/// 判断类型是否为 POD 结构体
template isPODStruct(T) {
    enum isPODStruct = is(T == struct) && !isDynamicArray!T && !isSomeString!T;
}

unittest {
    import std.stdio;

    writeln("[unittest] Slice 构造函数");
    {
        auto s1 = Slice(cast(const(ubyte)[])[1, 2, 3]);
        assert(s1.size() == 3);
        assert(s1.data() !is null);

        auto s2 = Slice("hello");
        assert(s2.size() == 5);

        int val = 42;
        auto s3 = Slice(&val, int.sizeof);
        assert(s3.size() == int.sizeof);
    }

    writeln("[unittest] Slice empty/ok/clear");
    {
        Slice s;
        assert(s.empty());
        assert(!s.ok());
        assert(s.size() == 0);

        auto s2 = Slice("abc");
        assert(!s2.empty());
        assert(s2.ok());

        s2.clear();
        assert(s2.empty());
        assert(s2.size() == 0);
    }

    writeln("[unittest] Slice asBytes/asString");
    {
        auto s = Slice("hello");
        auto bytes = s.asBytes();
        assert(bytes.length == 5);
        assert(bytes[0] == 'h');
        assert(bytes[4] == 'o');

        auto str = s.asString();
        assert(str == "hello");
    }

    writeln("[unittest] Slice as!T 类型转换");
    {
        auto s = Slice("world");
        assert(s.as!string() == "world");

        int val = 12345;
        auto s2 = Slice(&val, int.sizeof);
        assert(s2.as!int() == 12345);

        double dval = 3.14;
        auto s3 = Slice(&dval, double.sizeof);
        assert(s3.as!double() == 3.14);
    }

    writeln("[unittest] Slice Ref!T");
    {
        auto s = Slice.Ref(42);
        assert(s.size() == int.sizeof);
        assert(s.as!int() == 42);

        auto s2 = Slice.Ref(3.14);
        assert(s2.size() == double.sizeof);
        assert(s2.as!double() == 3.14);

        auto s3 = Slice.Ref(true);
        assert(s3.size() == bool.sizeof);
    }

    writeln("[unittest] Slice opCmp/opEquals");
    {
        auto s1 = Slice("abc");
        auto s2 = Slice("abc");
        auto s3 = Slice("abd");
        auto s4 = Slice("ab");

        assert(s1 == s2);
        assert(s1 != s3);
        assert(s1 != s4);
        assert(s1.opCmp(s3) < 0);
        assert(s3.opCmp(s1) > 0);
        assert(s1.opCmp(s2) == 0);
    }

    writeln("[unittest] Slice toHash");
    {
        auto s1 = Slice("hello");
        auto s2 = Slice("hello");
        auto s3 = Slice("world");

        assert(s1.toHash() == s2.toHash());
        assert(s1.toHash() != s3.toHash());

        Slice empty;
        assert(empty.toHash() == 0);
    }

    writeln("[unittest] Slice startsWith/endsWith");
    {
        auto s = Slice("hello world");

        assert(s.startsWith(Slice("hello")));
        assert(!s.startsWith(Slice("world")));
        assert(s.endsWith(Slice("world")));
        assert(!s.endsWith(Slice("hello")));
        assert(s.startsWith(Slice("")));
        assert(s.endsWith(Slice("")));
    }

    writeln("[unittest] Slice removePrefix");
    {
        auto s = Slice("hello world");
        auto s2 = s.removePrefix(6);
        assert(s2.asString() == "world");

        auto s3 = s.removePrefix(0);
        assert(s3.asString() == "hello world");
    }

    writeln("[unittest] Slice toString");
    {
        auto s = Slice("test");
        assert(s.toString() == "test");

        Slice empty;
        assert(empty.toString() == "");
    }

    writeln("[unittest] isPODStruct");
    {
        struct Point { int x; int y; }
        assert(isPODStruct!Point);
        assert(!isPODStruct!int);
        assert(!isPODStruct!string);
    }
}
