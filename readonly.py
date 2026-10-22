import ctypes
import os
import sys


def restrict_writes():
    libc = ctypes.CDLL(None, use_errno=True)
    abi = libc.syscall(444, 0, 0, 1)
    if abi < 1:
        raise OSError(ctypes.get_errno(), 'Landlock ABI query failed')
    rights = (1 << 1) | sum(1 << bit for bit in range(4, 13))
    if abi >= 2:
        rights |= 1 << 13
    if abi >= 3:
        rights |= 1 << 14

    class Ruleset(ctypes.Structure):
        _fields_ = [('handled_access_fs', ctypes.c_uint64)]

    class PathRule(ctypes.Structure):
        _pack_ = 1
        _fields_ = [('allowed_access', ctypes.c_uint64), ('parent_fd', ctypes.c_int32)]

    attributes = Ruleset(rights)
    descriptor = libc.syscall(444, ctypes.byref(attributes), ctypes.sizeof(attributes), 0)
    if descriptor < 0:
        raise OSError(ctypes.get_errno(), 'Landlock ruleset creation failed')
    try:
        for path in ['/tmp', '/dev/null', '/dev/tty', '/dev/ptmx', '/dev/pts']:
            if not os.path.exists(path):
                continue
            handle = os.open(path, os.O_PATH | os.O_CLOEXEC)
            try:
                allowed = rights if path == '/tmp' else ((1 << 1) | ((1 << 14) if abi >= 3 else 0))
                rule = PathRule(allowed, handle)
                if libc.syscall(445, descriptor, 1, ctypes.byref(rule), 0) != 0:
                    raise OSError(ctypes.get_errno(), 'Landlock path rule failed: ' + path)
            finally:
                os.close(handle)
        if libc.prctl(38, 1, 0, 0, 0) != 0:
            raise OSError(ctypes.get_errno(), 'no_new_privs failed')
        if libc.syscall(446, descriptor, 0) != 0:
            raise OSError(ctypes.get_errno(), 'Landlock enforcement failed')
    finally:
        os.close(descriptor)
    return abi


if __name__ == '__main__':
    print('Landlock ABI:', restrict_writes(), flush=True)
    if sys.argv[1:] == ['--verify']:
        try:
            descriptor = os.open('/home/nicholas/.config/nvimpager/nvimpager', os.O_WRONLY)
        except PermissionError:
            print('Repository write opens denied; no source file written.')
        else:
            os.close(descriptor)
            raise RuntimeError('Read-only guard did not restrict the repository')
        with open('/tmp/nvimpager-assessment.ZN1B0M/guard-check.txt', 'w') as handle:
            handle.write('temporary writes allowed\n')
    else:
        os.execvp(sys.argv[1], sys.argv[1:])
