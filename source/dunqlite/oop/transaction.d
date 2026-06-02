/**
 * 事务管理模块
 * 
 * 提供ACID事务支持
 */
module dunqlite.oop.transaction;

import dunqlite.oop.error;
import dunqlite.oop.storage;

/**
 * Transaction - 事务管理类
 * 
 * 提供事务的开始、提交和回滚功能
 */
class Transaction {
    /**
     * 事务状态枚举
     */
    private enum State {
        Inactive,      /// 未激活
        Active,        /// 激活中
        Committed,     /// 已提交
        RolledBack     /// 已回滚
    }
    
    private Storage storage_;
    private State state_;
    
    /**
     * 构造函数
     * 
     * 参数：
     *   storage = 关联的存储对象
     *   alloc = 内存分配器（未使用）
     */
    this(Storage storage) {
        storage_ = storage;
        state_ = State.Inactive;
    }
    
    /**
     * 开始事务
     * 
     * 返回：
     *   错误码
     */
    int begin() {
        if (state_ == State.Active) return ErrorCode.OK;
        state_ = State.Active;
        return ErrorCode.OK;
    }
    
    /**
     * 提交事务
     * 
     * 返回：
     *   错误码
     */
    int commit() {
        if (state_ != State.Active) return ErrorCode.INVALID;
        state_ = State.Committed;
        return ErrorCode.OK;
    }
    
    /**
     * 回滚事务
     * 
     * 返回：
     *   错误码
     */
    int rollback() {
        if (state_ != State.Active) return ErrorCode.INVALID;
        state_ = State.RolledBack;
        return ErrorCode.OK;
    }
    
    /**
     * 检查事务是否激活
     * 
     * 返回：
     *   是否激活
     */
    bool isActive() { return state_ == State.Active; }
}

unittest {
    import std.stdio;
    import dunqlite.oop.memory_storage;

    writeln("[unittest] Transaction begin/isActive");
    {
        auto ms = new MemoryStorage();
        auto tx = new Transaction(ms);
        scope(exit) destroy(tx);

        assert(!tx.isActive());
        int rc = tx.begin();
        assert(rc == ErrorCode.OK);
        assert(tx.isActive());
    }

    writeln("[unittest] Transaction commit");
    {
        auto ms = new MemoryStorage();
        auto tx = new Transaction(ms);
        scope(exit) destroy(tx);

        tx.begin();
        int rc = tx.commit();
        assert(rc == ErrorCode.OK);
        assert(!tx.isActive());
    }

    writeln("[unittest] Transaction rollback");
    {
        auto ms = new MemoryStorage();
        auto tx = new Transaction(ms);
        scope(exit) destroy(tx);

        tx.begin();
        int rc = tx.rollback();
        assert(rc == ErrorCode.OK);
        assert(!tx.isActive());
    }

    writeln("[unittest] Transaction 重复 begin");
    {
        auto ms = new MemoryStorage();
        auto tx = new Transaction(ms);
        scope(exit) destroy(tx);

        tx.begin();
        int rc = tx.begin();
        assert(rc == ErrorCode.OK);
        assert(tx.isActive());
    }

    writeln("[unittest] Transaction 未激活时 commit");
    {
        auto ms = new MemoryStorage();
        auto tx = new Transaction(ms);
        scope(exit) destroy(tx);

        int rc = tx.commit();
        assert(rc == ErrorCode.INVALID);
    }

    writeln("[unittest] Transaction 未激活时 rollback");
    {
        auto ms = new MemoryStorage();
        auto tx = new Transaction(ms);
        scope(exit) destroy(tx);

        int rc = tx.rollback();
        assert(rc == ErrorCode.INVALID);
    }

    writeln("[unittest] Transaction commit 后不可 rollback");
    {
        auto ms = new MemoryStorage();
        auto tx = new Transaction(ms);
        scope(exit) destroy(tx);

        tx.begin();
        tx.commit();
        int rc = tx.rollback();
        assert(rc == ErrorCode.INVALID);
    }
}
