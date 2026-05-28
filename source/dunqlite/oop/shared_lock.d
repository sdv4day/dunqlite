/**
 * 跨进程共享锁
 * 
 * 基于文件锁实现跨进程互斥
 * 支持读写锁语义（共享读/排他写）
 */
module dunqlite.oop.shared_lock;

import std.stdio;
import std.conv : text;

/**
 * SharedFileLock - 基于文件的跨进程锁
 * 
 * 使用操作系统文件锁实现跨进程互斥
 * 支持共享读锁和排他写锁
 */
final class SharedFileLock {
    private string lockFilePath_;
    private bool writeLocked_ = false;
    private bool readLocked_ = false;
    
    /**
     * 构造函数
     * 
     * 参数：
     *   path = 锁文件路径
     */
    this(string path) {
        lockFilePath_ = path;
    }
    
    ~this() {
        unlock();
    }
    
    /**
     * 获取排他写锁（阻塞）
     * 
     * 返回：
     *   是否成功
     */
    bool lockWrite() {
        version (Windows) {
            import core.sys.windows.windows;
            
            auto wpath = toWideString(lockFilePath_);
            auto hFile = CreateFileW(wpath.ptr,
                GENERIC_READ | GENERIC_WRITE,
                FILE_SHARE_READ | FILE_SHARE_WRITE,
                null, OPEN_ALWAYS,
                FILE_ATTRIBUTE_NORMAL, null);
            
            if (hFile == INVALID_HANDLE_VALUE) return false;
            
            OVERLAPPED overlapped;
            overlapped.Internal = 0;
            overlapped.InternalHigh = 0;
            overlapped.Offset = 0;
            overlapped.OffsetHigh = 0;
            overlapped.hEvent = null;
            
            auto rc = LockFileEx(hFile, LOCKFILE_EXCLUSIVE_LOCK, 0,
                0xFFFF_FFFF, 0xFFFF_FFFF, &overlapped);
            
            if (rc == 0) {
                CloseHandle(hFile);
                return false;
            }
            
            writeLocked_ = true;
            return true;
        }
        else version (Posix) {
            import core.sys.posix.fcntl;
            
            int fd = open(lockFilePath_.ptr, O_RDWR | O_CREAT, 438);
            if (fd < 0) return false;
            
            flock fl;
            fl.l_type = F_WRLCK;
            fl.l_whence = SEEK_SET;
            fl.l_start = 0;
            fl.l_len = 0;
            
            int rc = fcntl(fd, F_SETLKW, &fl);
            if (rc < 0) {
                close(fd);
                return false;
            }
            
            writeLocked_ = true;
            return true;
        }
        else {
            return false;
        }
    }
    
    /**
     * 获取共享读锁（阻塞）
     * 
     * 返回：
     *   是否成功
     */
    bool lockRead() {
        version (Windows) {
            import core.sys.windows.windows;
            
            auto wpath = toWideString(lockFilePath_);
            auto hFile = CreateFileW(wpath.ptr,
                GENERIC_READ, FILE_SHARE_READ,
                null, OPEN_ALWAYS,
                FILE_ATTRIBUTE_NORMAL, null);
            
            if (hFile == INVALID_HANDLE_VALUE) return false;
            
            OVERLAPPED overlapped;
            overlapped.Internal = 0;
            overlapped.InternalHigh = 0;
            overlapped.Offset = 0;
            overlapped.OffsetHigh = 0;
            overlapped.hEvent = null;
            
            auto rc = LockFileEx(hFile, 0, 0,
                0xFFFF_FFFF, 0xFFFF_FFFF, &overlapped);
            
            if (rc == 0) {
                CloseHandle(hFile);
                return false;
            }
            
            readLocked_ = true;
            return true;
        }
        else version (Posix) {
            import core.sys.posix.fcntl;
            
            int fd = open(lockFilePath_.ptr, O_RDWR | O_CREAT, 438);
            if (fd < 0) return false;
            
            flock fl;
            fl.l_type = F_RDLCK;
            fl.l_whence = SEEK_SET;
            fl.l_start = 0;
            fl.l_len = 0;
            
            int rc = fcntl(fd, F_SETLKW, &fl);
            if (rc < 0) {
                close(fd);
                return false;
            }
            
            readLocked_ = true;
            return true;
        }
        else {
            return false;
        }
    }
    
    /**
     * 释放锁
     */
    void unlock() {
        if (!writeLocked_ && !readLocked_) return;
        
        version (Windows) {
            import core.sys.windows.windows;
            
            auto wpath = toWideString(lockFilePath_);
            auto hFile = CreateFileW(wpath.ptr,
                GENERIC_READ | GENERIC_WRITE,
                FILE_SHARE_READ | FILE_SHARE_WRITE,
                null, OPEN_EXISTING,
                FILE_ATTRIBUTE_NORMAL, null);
            
            if (hFile != INVALID_HANDLE_VALUE) {
                OVERLAPPED overlapped;
                overlapped.Internal = 0;
                overlapped.InternalHigh = 0;
                overlapped.Offset = 0;
                overlapped.OffsetHigh = 0;
                overlapped.hEvent = null;
                
                UnlockFileEx(hFile, 0, 0xFFFF_FFFF, 0xFFFF_FFFF, &overlapped);
                CloseHandle(hFile);
            }
        }
        else version (Posix) {
            import core.sys.posix.fcntl;
            
            int fd = open(lockFilePath_.ptr, O_RDWR);
            if (fd >= 0) {
                flock fl;
                fl.l_type = F_UNLCK;
                fl.l_whence = SEEK_SET;
                fl.l_start = 0;
                fl.l_len = 0;
                fcntl(fd, F_SETLK, &fl);
                close(fd);
            }
        }
        
        writeLocked_ = false;
        readLocked_ = false;
    }
    
    /**
     * 尝试获取写锁（非阻塞）
     * 
     * 返回：
     *   是否成功
     */
    bool tryLockWrite() {
        version (Windows) {
            import core.sys.windows.windows;
            
            auto wpath = toWideString(lockFilePath_);
            auto hFile = CreateFileW(wpath.ptr,
                GENERIC_READ | GENERIC_WRITE,
                FILE_SHARE_READ | FILE_SHARE_WRITE,
                null, OPEN_ALWAYS,
                FILE_ATTRIBUTE_NORMAL, null);
            
            if (hFile == INVALID_HANDLE_VALUE) return false;
            
            OVERLAPPED overlapped;
            overlapped.Internal = 0;
            overlapped.InternalHigh = 0;
            overlapped.Offset = 0;
            overlapped.OffsetHigh = 0;
            overlapped.hEvent = null;
            
            auto rc = LockFileEx(hFile,
                LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY,
                0, 0xFFFF_FFFF, 0xFFFF_FFFF, &overlapped);
            
            if (rc == 0) {
                CloseHandle(hFile);
                return false;
            }
            
            writeLocked_ = true;
            return true;
        }
        else {
            return lockWrite();
        }
    }
    
    /// 是否持有写锁
    bool isWriteLocked() const { return writeLocked_; }
    
    /// 是否持有读锁
    bool isReadLocked() const { return readLocked_; }
    
    /// 获取锁文件路径
    string path() const { return lockFilePath_; }
    
private:
    version (Windows) {
        import core.sys.windows.windows;
        
        wchar[] toWideString(string s) {
            auto result = new wchar[](s.length + 1);
            int len = MultiByteToWideChar(CP_UTF8, 0,
                s.ptr, cast(int)s.length,
                result.ptr, cast(int)result.length);
            result[len] = 0;
            return result[0 .. len + 1];
        }
    }
}
