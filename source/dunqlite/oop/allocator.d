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
import core.sync.mutex;

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
            copyMemory(oldMem[0..newSize], newMem);
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
    private static shared Mutex instanceLock_;
    
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
                    auto lock = new Mutex();
                    auto alloc = new GlobalAllocator();
                    instanceLock_ = cast(shared) lock;
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
