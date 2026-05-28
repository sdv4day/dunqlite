/**
 * OOP模块 - 真正的面向对象设计
 * 
 * 类层次结构：
 *   Allocator (抽象基类)
 *       └── GlobalAllocator
 *   
 *   Storage (抽象基类)
 *       ├── MemoryStorage
 *       └── FileStorage
 *   
 *   Cursor (抽象基类)
 *       └── MemoryCursor
 *   
 *   Transaction
 *   Database (组合: Storage + Transaction)
 *   
 * 泛型接口：
 *   Database.put/get/del/find - 支持任意类型
 *   Slice - 零拷贝字节引用
 */
module dunqlite.oop;

public import dunqlite.oop.error;
public import dunqlite.oop.allocator;
public import dunqlite.oop.types;
public import dunqlite.oop.cursor;
public import dunqlite.oop.storage;
public import dunqlite.oop.memory_storage;
public import dunqlite.oop.file_storage;
public import dunqlite.oop.transaction;
public import dunqlite.oop.slice;
public import dunqlite.oop.shared_lock;
public import dunqlite.oop.database;
