/**
 * 存储抽象基类
 * 
 * 定义键值存储的标准接口
 */
module dunqlite.oop.storage;

import dunqlite.oop.error;
import dunqlite.oop.allocator;
import dunqlite.oop.cursor;
import core.atomic;

/**
 * Storage - 存储抽象基类
 * 
 * 定义键值存储的标准接口，支持不同的存储后端
 */
abstract class Storage {
    protected Allocator allocator_;
    
    /**
     * 构造函数
     * 
     * 参数：
     *   alloc = 内存分配器（null则使用全局分配器）
     */
    this(Allocator alloc = null) {
        allocator_ = alloc ? alloc : GlobalAllocator.instance();
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
    abstract int put(const(void)* key, int keyLen, const(void)* value, long valueLen);
    
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
    abstract int get(const(void)* key, int keyLen, void* buf, long* bufLen);
    
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
    abstract int remove(const(void)* key, int keyLen);
    
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
    abstract bool contains(const(void)* key, int keyLen);
    
    /**
     * 创建游标 - 工厂方法
     * 
     * 返回：
     *   游标实例
     */
    abstract Cursor createCursor();
    
    /**
     * 清空存储
     */
    abstract void clear();
    
    /**
     * 获取记录数量
     * 
     * 返回：
     *   记录数
     */
    abstract uint count();
    
    /**
     * 检查是否为空
     * 
     * 返回：
     *   是否为空
     */
    bool isEmpty() { return count() == 0; }
    
    /**
     * 获取内存分配器
     * 
     * 返回：
     *   Allocator实例
     */
    Allocator allocator() { return allocator_; }
}
