/**
 * KV存储示例 - 使用dunqlite OOP接口
 */
module examples.kv_demo;

import std.stdio : writeln, writefln;
import dunqlite.oop;

int main()
{
    writeln("DunQLite - D语言重构的UnQLite KV存储引擎 (OOP接口)");

    auto db = new Database();
    int rc = db.open();
    if (rc != ErrorCode.OK) {
        writefln("打开内存数据库失败: %d", rc);
        return 1;
    }
    writeln("内存数据库打开成功");

    // 字符串键值
    rc = db.put("hello", "world");
    if (rc == ErrorCode.OK) {
        writeln("KV存储成功: hello -> world");
    } else {
        writefln("KV存储失败: %d", rc);
    }

    string val;
    if (db.get("hello", val)) {
        writefln("KV读取成功: hello -> %s", val);
    } else {
        writeln("KV读取失败");
    }

    // 整数键值
    rc = db.put(42, 3.14);
    if (rc == ErrorCode.OK) {
        writeln("KV存储成功: 42 -> 3.14");
    }

    double dval;
    if (db.get(42, dval)) {
        writefln("KV读取成功: 42 -> %s", dval);
    }

    // 删除
    rc = db.del("hello");
    if (rc == ErrorCode.OK) {
        writeln("KV删除成功: hello");
    }

    writefln("记录数: %d", db.count());

    db.close();
    writeln("数据库关闭成功");
    return 0;
}
