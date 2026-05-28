/**
 * 游标抽象基类
 * 
 * 提供遍历存储数据的接口
 */
module dunqlite.oop.cursor;

import dunqlite.oop.storage;

/**
 * Cursor - 游标抽象基类
 * 
 * 提供遍历存储中所有记录的迭代器接口
 */
abstract class Cursor {
    protected Storage storage_;
    
    /**
     * 构造函数
     * 
     * 参数：
     *   storage = 关联的存储对象
     */
    this(Storage storage) {
        storage_ = storage;
    }
    
    /**
     * 移动到第一条记录
     * 
     * 返回：
     *   是否成功移动到记录
     */
    abstract bool moveFirst();
    
    /**
     * 移动到下一条记录
     * 
     * 返回：
     *   是否成功移动到记录
     */
    abstract bool moveNext();
    
    /**
     * 移动到最后一条记录
     * 
     * 返回：
     *   是否成功移动到记录
     */
    abstract bool moveLast();
    
    /**
     * 移动到前一条记录
     * 
     * 返回：
     *   是否成功移动到记录
     */
    abstract bool movePrevious();
    
    /**
     * 检查游标是否有效
     * 
     * 返回：
     *   当前位置是否有效
     */
    abstract bool isValid();
    
    /**
     * 获取当前记录的键
     * 
     * 返回：
     *   键数据指针
     */
    abstract const(void)* key();
    
    /**
     * 获取当前记录的键长度
     * 
     * 返回：
     *   键长度
     */
    abstract uint keyLength();
    
    /**
     * 获取当前记录的值
     * 
     * 返回：
     *   值数据指针
     */
    abstract const(void)* value();
    
    /**
     * 获取当前记录的值长度
     * 
     * 返回：
     *   值长度
     */
    abstract uint valueLength();
    
    /**
     * 删除当前记录
     * 
     * 返回：
     *   错误码
     */
    abstract int remove();
    
    /**
     * 重置游标到初始位置
     */
    abstract void reset();
    
    /**
     * 获取关联的存储对象
     * 
     * 返回：
     *   Storage实例
     */
    Storage storage() { return storage_; }
}
