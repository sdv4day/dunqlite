/**
 * 演示真正的OOP设计：
 * 
 * 1. 继承：Storage -> MemoryStorage
 * 2. 多态：Database.open()根据参数创建不同Storage
 * 3. 组合：Database包含Storage和Transaction
 * 4. 工厂方法：createCursor()
 * 5. 抽象：Cursor、Storage、Allocator都是抽象类
 */
module app;

import std.stdio;
import std.string;
import dunqlite.oop;

// 展示继承和多态：自定义存储实现
class LoggingStorage : MemoryStorage {
    this(Allocator alloc = null) {
        super(alloc);
        writeln("[LoggingStorage] 已创建");
    }
    
    override int put(const(void)* key, int keyLen, const(void)* value, long valueLen) {
        writefln("[LoggingStorage] put: key长度=%d, value长度=%d", keyLen, valueLen);
        return super.put(key, keyLen, value, valueLen);
    }
    
    override int get(const(void)* key, int keyLen, void* buf, long* bufLen) {
        writefln("[LoggingStorage] get: key长度=%d", keyLen);
        return super.get(key, keyLen, buf, bufLen);
    }
}

int main(string[] args) {
        version (Windows)
    {
        import core.sys.windows.windows;
        SetConsoleOutputCP(65001);
        SetConsoleCP(65001);
    }
    writeln("========================================");
    writeln(" OOP重构演示 - 真正的面向对象设计");
    writeln("========================================");
    writeln();
    
    // ==================== 演示1: 基本使用 ====================
    writeln("【演示1】基本CRUD操作");
    writeln("------------------------");
    
    auto db = new Database();
    db.open(null, true);
    writefln("数据库已打开，内存模式: %s", db.isInMemory() ? "是" : "否");
    
    // 存储
    db.put("name".ptr, 4, "DunQLite".ptr, 8);
    db.put("version".ptr, 7, "2.0.0".ptr, 5);
    db.put("type".ptr, 4, "KV-Store".ptr, 8);
    db.put("author".ptr, 6, "D-Language".ptr, 10);
    writefln("已存储 %d 条记录", db.count());
    writeln();
    
    // 读取
    char[256] buf;
    long len;
    
    len = buf.length;
    db.get("name".ptr, 4, buf.ptr, &len);
    auto nameStr = buf[0 .. cast(size_t)len].idup;
    writefln("读取 'name' = '%s'", nameStr);
    
    len = buf.length;
    db.get("version".ptr, 7, buf.ptr, &len);
    auto verStr = buf[0 .. cast(size_t)len].idup;
    writefln("读取 'version' = '%s'", verStr);
    writeln();
    
    // ==================== 演示2: 多态（继承） ====================
    writeln("【演示2】多态 - 使用LoggingStorage");
    writeln("------------------------");
    
    auto logStorage = new LoggingStorage();
    logStorage.put("test".ptr, 4, "value".ptr, 5);
    logStorage.put("demo".ptr, 4, "data".ptr, 4);
    writefln("LoggingStorage记录数: %d", logStorage.count());
    writeln();
    
    destroy(logStorage);
    
    // ==================== 演示3: 游标遍历 ====================
    writeln("【演示3】游标遍历（工厂方法）");
    writeln("------------------------");
    
    auto cursor = db.createCursor();
    cursor.moveFirst();
    
    writeln("遍历所有记录:");
    int idx = 0;
    while (cursor.isValid()) {
        auto keyBytes = cast(const(char)*)cursor.key();
        auto keyStr = keyBytes[0 .. cursor.keyLength()];
        auto valBytes = cast(const(char)*)cursor.value();
        auto valStr = valBytes[0 .. cursor.valueLength()];
        writefln("  [%d] %s = %s", idx, keyStr, valStr);
        cursor.moveNext();
        idx++;
    }
    writefln("共遍历 %d 条记录", idx);
    writeln();
    
    // ==================== 演示4: 组合关系 ====================
    writeln("【演示4】组合关系 - Database包含Storage和Transaction");
    writeln("------------------------");
    
    writeln("Database包含:");
    writefln("  - Storage: %s (记录数: %d)", 
             db.storage() !is null ? "有" : "无",
             db.storage() !is null ? db.storage().count() : 0);
    writefln("  - Transaction: %s", db.transaction() !is null ? "有" : "无");
    writefln("  - Allocator: %s", db.allocator() !is null ? "有" : "无");
    writeln();
    
    // ==================== 演示5: 事务 ====================
    writeln("【演示5】事务管理");
    writeln("------------------------");
    
    db.beginTransaction();
    writefln("事务已开始: %s", db.transaction().isActive() ? "是" : "否");
    
    db.put("trans_key".ptr, 9, "trans_value".ptr, 11);
    writefln("事务中添加数据，当前记录数: %d", db.count());
    
    db.rollback();
    writefln("事务已回滚，当前记录数: %d", db.count());
    writeln();
    
    // ==================== 演示6: 删除操作 ====================
    writeln("【演示6】删除操作");
    writeln("------------------------");
    
    writefln("删除前记录数: %d", db.count());
    db.remove("version".ptr, 7);
    writefln("删除 'version' 后记录数: %d", db.count());
    
    int rc = db.get("version".ptr, 7, buf.ptr, &len);
    writefln("尝试读取已删除的键: rc=%d (预期: %d)", rc, ErrorCode.NOT_FOUND);
    writeln();
    
    // ==================== 清理 ====================
    cursor.reset();
    destroy(cursor);
    db.close();
    destroy(db);
    
    writeln("========================================");
    writeln(" 演示完成");
    writeln("========================================");
    writeln();
    writeln("OOP特性总结:");
    writeln("  1. 封装: 数据和方法封装在类中");
    writeln("  2. 继承: MemoryStorage继承Storage");
    writeln("  3. 多态: LoggingStorage重写put/get方法");
    writeln("  4. 组合: Database组合Storage和Transaction");
    writeln("  5. 工厂方法: createCursor()创建游标");
    writeln("  6. 抽象类: Storage、Cursor、Allocator");
    
    return 0;
}
