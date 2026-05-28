/**
 * 泛型接口演示
 * 
 * 展示 Database.put/get/del/find 的泛型用法
 */
module app_generic;

import std.stdio;
import std.string;
import dunqlite.oop;

struct Point {
    int x;
    int y;
}

int main(string[] args) {
    version (Windows) {
        import core.sys.windows.windows;
        SetConsoleOutputCP(65001);
        SetConsoleCP(65001);
    }
    
    writeln("========================================");
    writeln(" 泛型接口演示 - Database.put/get/del/find");
    writeln("========================================");
    writeln();
    
    auto db = new Database();
    db.open(null, true);
    writefln("数据库已打开，内存模式: %s", db.isInMemory() ? "是" : "否");
    writeln();
    
    // ==================== 演示1: 字符串键值 ====================
    writeln("【演示1】字符串键值");
    writeln("------------------------");
    
    db.put("name", "DunQLite");
    db.put("version", "2.0.0");
    db.put("type", "KV-Store");
    
    string name;
    if (db.get("name", name)) {
        writefln("读取 'name' = '%s'", name);
    }
    
    string verStr = db.find("version", "unknown");
    writefln("查找 'version' = '%s'", verStr);
    
    string missing = db.find("missing", "default_value");
    writefln("查找不存在的键 'missing' = '%s'", missing);
    writeln();
    
    // ==================== 演示2: 整数值 ====================
    writeln("【演示2】整数值");
    writeln("------------------------");
    
    db.put("count", 42);
    db.put("price", 99.99);
    db.put("flag", true);
    
    int count;
    if (db.get("count", count)) {
        writefln("读取 'count' = %d", count);
    }
    
    double price;
    if (db.get("price", price)) {
        writefln("读取 'price' = %.2f", price);
    }
    
    bool flag;
    if (db.get("flag", flag)) {
        writefln("读取 'flag' = %s", flag);
    }
    writeln();
    
    // ==================== 演示3: 结构体 ====================
    writeln("【演示3】结构体");
    writeln("------------------------");
    
    Point p = Point(10, 20);
    db.put("point", p);
    
    Point p2;
    if (db.get("point", p2)) {
        writefln("读取 'point' = Point(%d, %d)", p2.x, p2.y);
    }
    writeln();
    
    // ==================== 演示4: 数组 ====================
    writeln("【演示4】数组");
    writeln("------------------------");
    
    int[] numbers = [1, 2, 3, 4, 5];
    db.put("numbers", numbers);
    
    int[] numbers2;
    if (db.get("numbers", numbers2)) {
        writefln("读取 'numbers' = %s", numbers2);
    }
    writeln();
    
    // ==================== 演示5: 运算符重载 ====================
    writeln("【演示5】运算符重载 db[key] 和 db[key] = val");
    writeln("------------------------");
    
    db["lang"] = "D语言";
    auto lang = db["lang"];
    writefln("db[\"lang\"] = '%s'", lang.asString());
    writeln();
    
    // ==================== 演示6: 删除 ====================
    writeln("【演示6】删除");
    writeln("------------------------");
    
    writefln("删除前记录数: %d", db.count());
    db.del("version");
    writefln("删除 'version' 后记录数: %d", db.count());
    
    string val;
    if (!db.get("version", val)) {
        writeln("'version' 已删除，无法读取");
    }
    writeln();
    
    // ==================== 演示7: Slice 直接操作 ====================
    writeln("【演示7】Slice 直接操作");
    writeln("------------------------");
    
    auto keySlice = Slice("slice_key");
    auto valSlice = Slice("slice_value");
    db.put(keySlice, valSlice);
    
    auto result = db.getSlice("slice_key");
    writefln("读取 Slice: '%s'", result.asString());
    writeln();
    
    // ==================== 清理 ====================
    db.close();
    destroy(db);
    
    writeln("========================================");
    writeln(" 演示完成");
    writeln("========================================");
    
    return 0;
}
