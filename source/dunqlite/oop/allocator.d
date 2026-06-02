/**
 * 内存分配器模块
 * 
 * 提供内存分配和管理的抽象接口及实现
 * 
 * 类层次：
 *   Allocator (抽象基类)
 *       └── GlobalAllocator (具体实现)
 */
module dunqlite.oop.allocator;

import std.experimental.allocator;
import std.experimental.allocator.mallocator;

/**
 * Allocator - 内存分配器抽象基类
 * 
 * 定义内存分配的标准接口，支持多种分配策略
 */
abstract class Allocator {
    /**
     * 分配指定大小的内存
     * 
     * 参数：
     *   size = 要分配的字节数
     * 
     * 返回：
     *   分配的内存块，失败时为空数组
     */
    abstract void[] allocate(size_t size);
    
    /**
     * 分配并初始化为零的内存
     * 
     * 参数：
     *   count = 元素数量
     *   size = 每个元素的大小
     * 
     * 返回：
     *   分配的内存块，失败时为空数组
     */
    abstract void[] allocateZero(size_t count, size_t size);
    
    /**
     * 释放内存
     * 
     * 参数：
     *   memory = 要释放的内存块
     */
    abstract void deallocate(void[] memory);
    
    /**
     * 复制内存数据
     * 
     * 参数：
     *   src = 源内存数据
     * 
     * 返回：
     *   新分配的内存块，包含源数据的副本
     */
    void[] duplicate(const(void)[] src) {
        auto mem = allocate(src.length);
        if (mem.length > 0) {
            copyMemory(src, mem);
        }
        return mem;
    }
    
    /**
     * 重新分配内存
     * 
     * 参数：
     *   oldMem = 原有内存块
     *   newSize = 新的大小
     * 
     * 返回：
     *   新分配的内存块
     */
    void[] reallocate(void[] oldMem, size_t newSize) {
        auto newMem = allocate(newSize);
        if (newMem.length == 0) return null;
        if (oldMem.length > 0) {
            auto copyLen = oldMem.length < newSize ? oldMem.length : newSize;
            copyMemory(oldMem[0..copyLen], newMem[0..copyLen]);
            deallocate(oldMem);
        }
        return newMem;
    }
    
    /**
     * 内存复制辅助函数
     * 
     * 使用D标准方法进行内存复制
     * 
     * 参数：
     *   src = 源内存
     *   dst = 目标内存
     */
    static void copyMemory(const(void)[] src, void[] dst) {
        auto srcBytes = cast(const(ubyte)[])src;
        auto dstBytes = cast(ubyte[])dst;
        size_t len = srcBytes.length < dstBytes.length ? srcBytes.length : dstBytes.length;
        dstBytes[0 .. len] = srcBytes[0 .. len];
    }
}

/**
 * GlobalAllocator - 全局内存分配器
 * 
 * 使用Mallocator（标准C库malloc）的分配器实现
 * 单例模式确保全局唯一实例
 */
final class GlobalAllocator : Allocator {
    private static shared GlobalAllocator instance_;
    
    /**
     * 获取全局实例（线程安全）
     * 
     * 返回：
     *   GlobalAllocator的唯一实例
     */
    static GlobalAllocator instance() {
        if (instance_ is null) {
            synchronized {
                if (instance_ is null) {
                    auto alloc = new GlobalAllocator();
                    instance_ = cast(shared) alloc;
                }
            }
        }
        return cast(GlobalAllocator) instance_;
    }
    
    override void[] allocate(size_t size) {
        return Mallocator.instance.allocate(size);
    }
    
    override void[] allocateZero(size_t count, size_t size) {
        auto mem = Mallocator.instance.allocate(count * size);
        if (mem.length > 0) {
            auto bytes = cast(ubyte[])mem;
            bytes[] = 0;
        }
        return mem;
    }
    
    override void deallocate(void[] memory) {
        Mallocator.instance.deallocate(memory);
    }
}

unittest {
    import std.stdio;

    writeln("[unittest] GlobalAllocator.instance 单例");
    {
        auto a1 = GlobalAllocator.instance();
        auto a2 = GlobalAllocator.instance();
        assert(a1 !is null);
        assert(a1 is a2);
    }

    writeln("[unittest] GlobalAllocator.allocate/deallocate");
    {
        auto alloc = GlobalAllocator.instance();
        auto mem = alloc.allocate(1024);
        assert(mem.length == 1024);
        (cast(ubyte[])mem)[0] = 0xAB;
        assert((cast(ubyte[])mem)[0] == 0xAB);
        alloc.deallocate(mem);
    }

    writeln("[unittest] GlobalAllocator.allocateZero");
    {
        auto alloc = GlobalAllocator.instance();
        auto mem = alloc.allocateZero(10, 4);
        assert(mem.length == 40);
        auto bytes = cast(ubyte[])mem;
        foreach (b; bytes) {
            assert(b == 0);
        }
        alloc.deallocate(mem);
    }

    writeln("[unittest] Allocator.duplicate");
    {
        auto alloc = GlobalAllocator.instance();
        auto src = cast(const(void)[])"hello";
        auto mem = alloc.duplicate(src);
        assert(mem.length == 5);
        assert((cast(ubyte[])mem)[0] == 'h');
        assert((cast(ubyte[])mem)[4] == 'o');
        alloc.deallocate(mem);
    }

    writeln("[unittest] Allocator.reallocate");
    {
        auto alloc = GlobalAllocator.instance();
        auto mem = alloc.allocate(16);
        (cast(ubyte[])mem)[0] = 0xFF;
        auto mem2 = alloc.reallocate(mem, 32);
        assert(mem2.length == 32);
        assert((cast(ubyte[])mem2)[0] == 0xFF);
        alloc.deallocate(mem2);
    }

    writeln("[unittest] Allocator.copyMemory");
    {
        ubyte[4] src = [1, 2, 3, 4];
        ubyte[4] dst;
        Allocator.copyMemory(src[], dst[]);
        assert(dst[0] == 1);
        assert(dst[3] == 4);

        ubyte[2] dst2;
        Allocator.copyMemory(src[], dst2[]);
        assert(dst2[0] == 1);
        assert(dst2[1] == 2);
    }
}
