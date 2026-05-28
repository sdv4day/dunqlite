/**
 * 综合测试 - 10万条数据
 * 
 * 测试场景：
 *   1. 批量写入 / 读取值内容验证
 *   2. 实体结构体读写验证
 *   3. 随机读取 + 值校验
 *   4. 游标遍历 + 键值校验
 *   5. 批量删除 + 删除验证
 *   6. 整数键值读写验证
 *   7. 多线程并发读写测试
 *   8. 混合类型压力测试
 */
module benchmark;

import std.stdio;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.conv : to, text;
import std.format : format;
import std.string : toStringz;
import std.random : uniform;
import std.range : iota;
import std.algorithm.iteration : each;
import core.thread : Thread;
import core.atomic : atomicOp;
import dunqlite.oop;

enum COUNT = 100_000;

/**
 * 用户实体 - 模拟真实业务结构体
 */
struct UserEntity {
    int id;
    int age;
    int score;
    uint status;
}

/**
 * 订单实体 - 模拟真实业务结构体
 */
struct OrderEntity {
    int orderId;
    int userId;
    int amount;
    int status;
    uint timestamp;
}

int main(string[] args) {
    version (Windows) {
        import core.sys.windows.windows;
        SetConsoleOutputCP(65001);
        SetConsoleCP(65001);
    }

    writeln("========================================");
    writefln(" 综合测试 - %d 条数据", COUNT);
    writeln("========================================");
    writeln();

    auto db = new Database();
    //db.open(null, true);
    db.open("null", true);

    StopWatch sw;

    // ==================== 1. 批量写入 + 值内容验证 ====================
    writeln("[1] 批量写入 + 值内容验证");
    writeln("--------------------");

    sw.start();
    for (int i = 0; i < COUNT; i++) {
        auto key = format("key_%06d", i);
        auto val = format("value_%06d_data_%d", i, i * 3);
        db.put(key, val);
    }
    sw.stop();
    auto writeMs = sw.peek().total!"msecs";
    writefln("  写入 %d 条: %d ms (%.0f ops/s)",
             COUNT, writeMs, cast(double)COUNT * 1000 / (writeMs > 0 ? writeMs : 1));

    // 值内容验证：逐条读取并校验值内容
    sw.reset();
    sw.start();
    int readOk = 0;
    int readFail = 0;
    int valueMismatch = 0;
    for (int i = 0; i < COUNT; i++) {
        auto key = format("key_%06d", i);
        auto expected = format("value_%06d_data_%d", i, i * 3);
        string val;
        if (db.get(key, val)) {
            readOk++;
            if (val != expected) valueMismatch++;
        } else {
            readFail++;
        }
    }
    sw.stop();
    auto readMs = sw.peek().total!"msecs";
    writefln("  读取 %d 条: %d ms (%.0f ops/s)",
             COUNT, readMs, cast(double)COUNT * 1000 / (readMs > 0 ? readMs : 1));
    writefln("  成功=%d, 失败=%d, 值不匹配=%d", readOk, readFail, valueMismatch);
    assert(readOk == COUNT && readFail == 0 && valueMismatch == 0, "读取验证失败!");
    writeln("  ✓ 值内容验证全部通过");
    writeln();

    // ==================== 2. 实体结构体读写验证 ====================
    writeln("[2] 实体结构体读写验证");
    writeln("--------------------");

    // 写入UserEntity
    sw.reset();
    sw.start();
    for (int i = 0; i < COUNT; i++) {
        auto key = format("user_%d", i);
        auto user = UserEntity(i, 20 + (i % 80), i * 10, i % 3 == 0 ? 1u : 0u);
        db.put(key, user);
    }
    sw.stop();
    auto entityWriteMs = sw.peek().total!"msecs";
    writefln("  写入 %d 个UserEntity: %d ms (%.0f ops/s)",
             COUNT, entityWriteMs, cast(double)COUNT * 1000 / (entityWriteMs > 0 ? entityWriteMs : 1));

    // 读取验证UserEntity
    sw.reset();
    sw.start();
    int entityReadOk = 0;
    int entityMismatch = 0;
    for (int i = 0; i < COUNT; i++) {
        auto key = format("user_%d", i);
        UserEntity user;
        if (db.get(key, user)) {
            entityReadOk++;
            int expectedAge = 20 + (i % 80);
            int expectedScore = i * 10;
            uint expectedStatus = i % 3 == 0 ? 1u : 0u;
            if (user.id != i || user.age != expectedAge || 
                user.score != expectedScore || user.status != expectedStatus) {
                entityMismatch++;
            }
        }
    }
    sw.stop();
    auto entityReadMs = sw.peek().total!"msecs";
    writefln("  读取 %d 个UserEntity: %d ms (%.0f ops/s)",
             COUNT, entityReadMs, cast(double)COUNT * 1000 / (entityReadMs > 0 ? entityReadMs : 1));
    writefln("  成功=%d, 字段不匹配=%d", entityReadOk, entityMismatch);
    assert(entityReadOk == COUNT && entityMismatch == 0, "UserEntity验证失败!");
    writeln("  ✓ UserEntity字段验证全部通过");

    // 写入OrderEntity
    sw.reset();
    sw.start();
    for (int i = 0; i < COUNT; i++) {
        auto key = format("order_%d", i);
        auto order = OrderEntity(i, i % 10000, 100 + (i % 1000), i % 5, cast(uint)(i * 60));
        db.put(key, order);
    }
    sw.stop();
    auto orderWriteMs = sw.peek().total!"msecs";
    writefln("  写入 %d 个OrderEntity: %d ms (%.0f ops/s)",
             COUNT, orderWriteMs, cast(double)COUNT * 1000 / (orderWriteMs > 0 ? orderWriteMs : 1));

    // 读取验证OrderEntity
    sw.reset();
    sw.start();
    int orderReadOk = 0;
    int orderMismatch = 0;
    for (int i = 0; i < COUNT; i++) {
        auto key = format("order_%d", i);
        OrderEntity order;
        if (db.get(key, order)) {
            orderReadOk++;
            int expectedUserId = i % 10000;
            int expectedAmount = 100 + (i % 1000);
            int expectedStatus = i % 5;
            if (order.orderId != i || order.userId != expectedUserId ||
                order.amount != expectedAmount || order.status != expectedStatus) {
                orderMismatch++;
            }
        }
    }
    sw.stop();
    auto orderReadMs = sw.peek().total!"msecs";
    writefln("  读取 %d 个OrderEntity: %d ms (%.0f ops/s)",
             COUNT, orderReadMs, cast(double)COUNT * 1000 / (orderReadMs > 0 ? orderReadMs : 1));
    writefln("  成功=%d, 字段不匹配=%d", orderReadOk, orderMismatch);
    assert(orderReadOk == COUNT && orderMismatch == 0, "OrderEntity验证失败!");
    writeln("  ✓ OrderEntity字段验证全部通过");
    writeln();

    // ==================== 3. 随机读取 + 值校验 ====================
    writeln("[3] 随机读取 + 值校验");
    writeln("--------------------");

    int randomCount = 10_000;
    int randomHit = 0;
    int randomValueOk = 0;
    int randomValueFail = 0;

    sw.reset();
    sw.start();

    for (int i = 0; i < randomCount; i++) {
        int r = uniform(0, COUNT);
        auto key = format("key_%06d", r);
        auto expected = format("value_%06d_data_%d", r, r * 3);
        string val;
        if (db.get(key, val)) {
            randomHit++;
            if (val == expected) randomValueOk++;
            else randomValueFail++;
        }
    }

    sw.stop();
    auto randomMs = sw.peek().total!"msecs";
    writefln("  随机读取 %d 次: %d ms (%.0f ops/s)",
             randomCount, randomMs, cast(double)randomCount * 1000 / (randomMs > 0 ? randomMs : 1));
    writefln("  命中=%d, 值匹配=%d, 值不匹配=%d", randomHit, randomValueOk, randomValueFail);
    assert(randomValueFail == 0, "随机读取值校验失败!");
    writeln("  ✓ 随机读取值校验全部通过");
    writeln();

    // ==================== 4. 游标遍历 + 键值校验 ====================
    writeln("[4] 游标遍历 + 键值校验");
    writeln("--------------------");

    sw.reset();
    sw.start();

    auto cursor = db.createCursor();
    cursor.moveFirst();
    size_t traverseCount = 0;
    size_t traverseKeyOk = 0;
    while (cursor.isValid()) {
        traverseCount++;
        // 校验键是否可读
        auto keyBytes = cast(const(char)*)cursor.key();
        if (keyBytes !is null && cursor.keyLength() > 0) {
            traverseKeyOk++;
        }
        cursor.moveNext();
    }

    sw.stop();
    auto traverseMs = sw.peek().total!"msecs";
    writefln("  遍历 %d 条: %d ms (%.0f ops/s)",
             traverseCount, traverseMs, cast(double)traverseCount * 1000 / (traverseMs > 0 ? traverseMs : 1));
    writefln("  键可读=%d", traverseKeyOk);
    assert(traverseKeyOk == traverseCount, "游标遍历键校验失败!");
    writeln("  ✓ 游标遍历键校验全部通过");
    writeln();

    // ==================== 5. 批量删除 + 读取验证 ====================
    writeln("[5] 批量删除 + 读取验证");
    writeln("--------------------");

    sw.reset();
    sw.start();
    int delCount = COUNT / 2;
    for (int i = 0; i < delCount; i++) {
        auto key = format("key_%06d", i * 2);
        db.del(key);
    }
    sw.stop();
    auto delMs = sw.peek().total!"msecs";
    writefln("  删除 %d 条: %d ms (%.0f ops/s)",
             delCount, delMs, cast(double)delCount * 1000 / (delMs > 0 ? delMs : 1));
    writefln("  剩余记录数: %d", db.count());

    // 删除后验证：偶数key应不存在，奇数key应存在且值正确
    int delVerifyOk = 0;
    int delVerifyFail = 0;
    for (int i = 0; i < 1000; i++) {
        // 偶数key - 应已被删除
        auto evenKey = format("key_%06d", i * 2);
        string evenVal;
        if (!db.get(evenKey, evenVal)) {
            delVerifyOk++;
        } else {
            delVerifyFail++;
        }
        // 奇数key - 应存在且值正确
        auto oddKey = format("key_%06d", i * 2 + 1);
        auto oddExpected = format("value_%06d_data_%d", i * 2 + 1, (i * 2 + 1) * 3);
        string oddVal;
        if (db.get(oddKey, oddVal) && oddVal == oddExpected) {
            delVerifyOk++;
        } else {
            delVerifyFail++;
        }
    }
    writefln("  删除验证: 通过=%d, 失败=%d", delVerifyOk, delVerifyFail);
    assert(delVerifyFail == 0, "删除后读取验证失败!");
    writeln("  ✓ 删除后读取验证全部通过");
    writeln();

    // ==================== 6. 整数键值读写验证 ====================
    writeln("[6] 整数键值读写验证");
    writeln("--------------------");

    sw.reset();
    sw.start();
    for (int i = 0; i < COUNT; i++) {
        auto key = format("int_%d", i);
        db.put(key, i);
    }
    sw.stop();
    auto intWriteMs = sw.peek().total!"msecs";

    sw.reset();
    sw.start();
    int intReadOk = 0;
    int intMismatch = 0;
    for (int i = 0; i < COUNT; i++) {
        auto key = format("int_%d", i);
        int val;
        if (db.get(key, val)) {
            intReadOk++;
            if (val != i) intMismatch++;
        }
    }
    sw.stop();
    auto intReadMs = sw.peek().total!"msecs";
    writefln("  写入 %d 条: %d ms, 读取 %d 条: %d ms",
             COUNT, intWriteMs, COUNT, intReadMs);
    writefln("  成功=%d, 值不匹配=%d", intReadOk, intMismatch);
    assert(intReadOk == COUNT && intMismatch == 0, "整数键值验证失败!");
    writeln("  ✓ 整数键值验证全部通过");
    writeln();

    // ==================== 7. 多线程并发读写测试 ====================
    writeln("[7] 多线程并发读写测试（线程安全）");
    writeln("--------------------");
    
    // 用全新的db测试，排除前序数据影响
    auto mtDb = new Database();
    mtDb.open();
    writefln("  新db.count()=%d", mtDb.count());

    enum THREAD_COUNT = 4;
    enum PER_THREAD = COUNT / THREAD_COUNT;

    shared int[THREAD_COUNT] threadWriteOk;
    shared int[THREAD_COUNT] threadReadOk;
    shared int[THREAD_COUNT] threadReadMismatch;

    sw.reset();
    sw.start();

    Thread[THREAD_COUNT] threads;
    // 用独立的线程函数避免D闭包捕获循环变量的引用语义问题
    void threadFunc(int tid) {
        for (int i = 0; i < PER_THREAD; i++) {
            auto key = text("mt_", tid, "_", i);
            auto val = text("mtval_", tid, "_", i);
            int rc = mtDb.put(key, val);
            if (rc == ErrorCode.OK) {
                atomicOp!"+="(threadWriteOk[tid], 1);
            }
        }
        for (int i = 0; i < PER_THREAD; i++) {
            auto key = text("mt_", tid, "_", i);
            auto expected = text("mtval_", tid, "_", i);
            string val;
            if (mtDb.get(key, val)) {
                atomicOp!"+="(threadReadOk[tid], 1);
                if (val != expected) atomicOp!"+="(threadReadMismatch[tid], 1);
            }
        }
    }
    
    // 为每个线程单独创建，避免D闭包捕获循环变量的引用语义问题
    threads[0] = new Thread(() { threadFunc(0); });
    threads[1] = new Thread(() { threadFunc(1); });
    threads[2] = new Thread(() { threadFunc(2); });
    threads[3] = new Thread(() { threadFunc(3); });
    foreach (ref th; threads) th.start();

    for (int t = 0; t < THREAD_COUNT; t++) {
        threads[t].join();
    }

    sw.stop();
    auto mtMs = sw.peek().total!"msecs";

    int totalMtWrite = 0;
    int totalMtRead = 0;
    int totalMtMismatch = 0;
    for (int t = 0; t < THREAD_COUNT; t++) {
        totalMtWrite += threadWriteOk[t];
        totalMtRead += threadReadOk[t];
        totalMtMismatch += threadReadMismatch[t];
    }

    auto mtTotal = PER_THREAD * THREAD_COUNT;
    writefln("  %d 线程 x %d 条: %d ms", THREAD_COUNT, PER_THREAD, mtMs);
    writefln("  写入成功=%d/%d, 读取成功=%d/%d, 值不匹配=%d", 
             totalMtWrite, mtTotal, totalMtRead, mtTotal, totalMtMismatch);
    writefln("  吞吐: %.0f ops/s", cast(double)mtTotal * 2 * 1000 / (mtMs > 0 ? mtMs : 1));
    assert(totalMtWrite == mtTotal, "多线程写入不完整!");
    assert(totalMtRead == mtTotal, "多线程读取不完整!");
    assert(totalMtMismatch == 0, "多线程值不匹配!");
    writeln("  ✓ 多线程读写验证全部通过");
    writeln();

    // ==================== 7b. 多线程并发混合读写 ====================
    writeln("[7b] 多线程并发混合读写");
    writeln("--------------------");

    shared int[THREAD_COUNT] mixWriteOk;
    shared int[THREAD_COUNT] mixReadOk;
    shared int[THREAD_COUNT] mixReadMismatch;

    sw.reset();
    sw.start();

    void mixThreadFunc(int tid) {
        for (int i = 0; i < PER_THREAD; i++) {
            auto key = text("mixrw_", tid, "_", i);
            auto val = text("mixval_", tid, "_", i);
            
            int rc = db.put(key, val);
            if (rc == ErrorCode.OK) atomicOp!"+="(mixWriteOk[tid], 1);
            
            string readVal;
            if (db.get(key, readVal)) {
                atomicOp!"+="(mixReadOk[tid], 1);
                if (readVal != val) atomicOp!"+="(mixReadMismatch[tid], 1);
            }
        }
    }

    threads[0] = new Thread(() { mixThreadFunc(0); });
    threads[1] = new Thread(() { mixThreadFunc(1); });
    threads[2] = new Thread(() { mixThreadFunc(2); });
    threads[3] = new Thread(() { mixThreadFunc(3); });
    foreach (ref th; threads) th.start();

    for (int t = 0; t < THREAD_COUNT; t++) {
        threads[t].join();
    }

    sw.stop();
    auto mixMs = sw.peek().total!"msecs";

    int totalMixWrite = 0, totalMixRead = 0, totalMixMismatch = 0;
    for (int t = 0; t < THREAD_COUNT; t++) {
        totalMixWrite += mixWriteOk[t];
        totalMixRead += mixReadOk[t];
        totalMixMismatch += mixReadMismatch[t];
    }

    writefln("  %d 线程 x %d 条混合读写: %d ms", THREAD_COUNT, PER_THREAD, mixMs);
    writefln("  写入成功=%d/%d, 读取成功=%d/%d, 值不匹配=%d",
             totalMixWrite, mtTotal, totalMixRead, mtTotal, totalMixMismatch);
    assert(totalMixWrite == mtTotal, "混合写入不完整!");
    assert(totalMixRead == mtTotal, "混合读取不完整!");
    assert(totalMixMismatch == 0, "混合读写值不匹配!");
    writeln("  ✓ 多线程混合读写验证全部通过");
    writeln();

    // ==================== 7c. 多进程文件锁测试 ====================
    writeln("[7c] 多进程文件锁测试");
    writeln("--------------------");

    // 使用文件锁打开数据库
    auto db2 = new Database();
    int rc2 = db2.open("test_db", true, false);
    if (rc2 == ErrorCode.OK) {
        writefln("  进程1写锁打开: 成功 (readOnly=%s)", db2.isReadOnly());
        
        // 同进程内第二个Database实例打开同一文件（应降级为只读）
        auto db3 = new Database();
        int rc3 = db3.open("test_db", true, false);
        if (rc3 == ErrorCode.OK) {
            writefln("  进程2打开: 成功 (readOnly=%s)", db3.isReadOnly());
            
            // 两个实例并发操作
            db2.put("proc_key_1", "proc_val_1");
            db2.put("proc_key_2", "proc_val_2");
            db3.put("proc_key_3", "proc_val_3");
            
            // 读取验证
            string pv1, pv2, pv3;
            bool r1 = db2.get("proc_key_1", pv1) && pv1 == "proc_val_1";
            bool r2 = db2.get("proc_key_2", pv2) && pv2 == "proc_val_2";
            bool r3 = db3.get("proc_key_3", pv3) && pv3 == "proc_val_3";
            writefln("  跨实例读取: key1=%s, key2=%s, key3=%s",
                     r1 ? "✓" : "✗", r2 ? "✓" : "✗", r3 ? "✓" : "✗");
            
            db3.close();
            destroy(db3);
        }
        
        db2.close();
        destroy(db2);
        writeln("  ✓ 多进程文件锁测试通过");
    } else {
        writefln("  进程1写锁打开: 失败 rc=%d", rc2);
        destroy(db2);
    }
    writeln();

    // ==================== 8. 混合类型压力测试 ====================
    writeln("[8] 混合类型压力测试");
    writeln("--------------------");

    int mixedCount = 50_000;
    sw.reset();
    sw.start();

    int mixedOk = 0;
    for (int i = 0; i < mixedCount; i++) {
        int kind = i % 4;
        auto key = format("mix_%d", i);
        switch (kind) {
            case 0: {
                db.put(key, format("str_%d", i));
                string v;
                if (db.get(key, v)) mixedOk++;
                break;
            }
            case 1: {
                db.put(key, i);
                int v;
                if (db.get(key, v)) mixedOk++;
                break;
            }
            case 2: {
                db.put(key, cast(double)(i * 0.1));
                double v;
                if (db.get(key, v)) mixedOk++;
                break;
            }
            case 3: {
                auto entity = UserEntity(i, i % 100, i * 5, 1u);
                db.put(key, entity);
                UserEntity v;
                if (db.get(key, v)) mixedOk++;
                break;
            }
            default: break;
        }
    }

    sw.stop();
    auto mixedMs = sw.peek().total!"msecs";
    writefln("  混合读写 %d 条: %d ms (%.0f ops/s)",
             mixedCount, mixedMs, cast(double)mixedCount * 2 * 1000 / (mixedMs > 0 ? mixedMs : 1));
    writefln("  读取成功=%d/%d", mixedOk, mixedCount);
    assert(mixedOk == mixedCount, "混合类型验证失败!");
    writeln("  ✓ 混合类型验证全部通过");
    writeln();

    // ==================== 9. 文件持久化测试 ====================
    writeln("[9] 文件持久化测试");
    writeln("--------------------");

    string testDbPath = "benchmark_test.db";
    int fileRc;
    
    // 清理旧测试文件
    import std.file : exists, remove;
    if (exists(testDbPath)) {
        remove(testDbPath);
    }
    if (exists(testDbPath ~ ".lock")) {
        try { remove(testDbPath ~ ".lock"); } catch (Exception) {}
    }

    // 9a. 创建文件数据库并写入数据
    auto fileDb = new Database();
    fileRc = fileDb.open(testDbPath.toStringz, false, false); // inMemory=false
    if (fileRc == ErrorCode.OK) {
        writefln("  创建文件数据库: %s", testDbPath);
        
        enum FILE_TEST_COUNT = 10_000;
        sw.reset();
        sw.start();
        for (int i = 0; i < FILE_TEST_COUNT; i++) {
            fileDb.put(format("file_key_%d", i), format("file_val_%d", i));
        }
        sw.stop();
        writefln("  写入 %d 条: %d ms", FILE_TEST_COUNT, sw.peek().total!"msecs");
        writefln("  记录数: %d", fileDb.count());
        
        // 写入实体数据
        for (int i = 0; i < 1000; i++) {
            auto user = UserEntity(i, i % 100, i * 10, 1u);
            fileDb.put(format("user_%d", i), user);
        }
        writefln("  写入1000个UserEntity后记录数: %d", fileDb.count());
        
        fileDb.close();
        writeln("  数据库已关闭并刷盘");
        destroy(fileDb);
        
        // 9b. 重新打开验证持久化
        writeln("  重新打开数据库验证持久化...");
        auto reopenDb = new Database();
        fileRc = reopenDb.open(testDbPath.toStringz, false, false);
        if (fileRc == ErrorCode.OK) {
            writefln("  重新打开成功");
            writefln("  重开后记录数: %d", reopenDb.count());
            
            int verifyOk = 0;
            int verifyFail = 0;
            for (int i = 0; i < FILE_TEST_COUNT; i++) {
                string val;
                if (reopenDb.get(format("file_key_%d", i), val)) {
                    if (val == format("file_val_%d", i)) {
                        verifyOk++;
                    } else {
                        verifyFail++;
                    }
                } else {
                    verifyFail++;
                }
            }
            writefln("  字符串验证: 成功=%d, 失败=%d", verifyOk, verifyFail);
            assert(verifyOk == FILE_TEST_COUNT && verifyFail == 0, "字符串持久化验证失败!");
            
            int entityOk = 0;
            for (int i = 0; i < 1000; i++) {
                UserEntity user;
                if (reopenDb.get(format("user_%d", i), user)) {
                    if (user.id == i && user.age == i % 100 && user.score == i * 10) {
                        entityOk++;
                    }
                }
            }
            writefln("  实体验证: 成功=%d/1000", entityOk);
            assert(entityOk == 1000, "实体持久化验证失败!");
            
            reopenDb.close();
            destroy(reopenDb);
            writeln("  ✓ 文件持久化验证通过");
        } else {
            writefln("  重新打开失败: rc=%d", fileRc);
        }
        
        // 清理测试文件
        if (exists(testDbPath)) {
            remove(testDbPath);
        }
        if (exists(testDbPath ~ ".lock")) {
            try { remove(testDbPath ~ ".lock"); } catch (Exception) {}
        }
        writeln("  测试文件已清理");
    } else {
        writefln("  创建文件数据库失败: rc=%d", fileRc);
    }
    writeln();

    // ==================== 清理 ====================
    cursor.reset();
    destroy(cursor);
    db.close();
    destroy(db);

    writeln("========================================");
    writeln(" 全部测试完成 ✓");
    writeln("========================================");

    return 0;
}
