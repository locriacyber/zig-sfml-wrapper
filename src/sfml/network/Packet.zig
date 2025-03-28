//! Utility class to build blocks of data to transfer over the network.

const std = @import("std");
const sf = @import("../sfml.zig");

const Packet = @This();

// Constructor/destructor

/// Inits an empty packet
pub fn create() !Packet {
    var pack = sf.c.sfPacket_create();
    if (pack) |p| {
        return Packet{ ._ptr = p };
    } else return sf.Error.nullptrUnknownReason;
}
/// Destroys a packet
pub fn destroy(self: *Packet) void {
    sf.c.sfPacket_destroy(self._ptr);
}
/// Copies a packet
pub fn copy(self: Packet) !Packet {
    var pack = sf.c.sfPacket_copy(self._ptr);
    if (pack) |p| {
        return Packet{ ._ptr = p };
    } else return sf.Error.nullptrUnknownReason;
}

// Getters/Setters

/// Empties this packet of its data
pub fn clear(self: *Packet) void {
    sf.c.sfPacket_clear(self._ptr);
}

/// Gets a const slice of this packet's content
/// Do not store, pointer may be changed when editing data
/// Be careful when using that in conjunction with read or reader
/// This gets all the data and does not move the reader
pub fn getData(self: Packet) []const u8 {
    const data = sf.c.sfPacket_getData(self._ptr);
    const size = sf.c.sfPacket_getDataSize(self._ptr);

    var slice: []const u8 = undefined;
    slice.ptr = @ptrCast([*]const u8, data);
    slice.len = size;
    return slice;
}
/// Gets the data size in bytes inside this packet
pub fn getDataSize(self: Packet) usize {
    return sf.c.sfPacket_getDataSize(self._ptr);
}

/// Appends bytes to the packet. You can also use the writer()
pub fn append(self: *Packet, data: []const u8) !void {
    const size_a = self.getDataSize();
    sf.c.sfPacket_append(self._ptr, data.ptr, data.len);
    const size_b = self.getDataSize();
    const size = size_b - size_a;
    if (size != data.len)
        return sf.Error.cannotWriteToPacket;
}

/// Returns false if the packet is ready for reading, true if there is no more data
pub fn isAtEnd(self: Packet) bool {
    return sf.c.sfPacket_endOfPacket(self._ptr) != 0;
}
/// Returns an error if last read operation failed
fn checkLastRead(self: Packet) !void {
    if (sf.c.sfPacket_canRead(self._ptr) == 0)
        return sf.Error.couldntRead;
}

/// Reads a type from the packet
/// Slightly faster than using a reader for bigger types
pub fn read(self: *Packet, comptime T: type) !T {
    const res: T = switch (T) {
        bool => (sf.c.sfPacket_readBool(self._ptr) != 0),
        i8 => sf.c.sfPacket_readInt8(self._ptr),
        u8 => sf.c.sfPacket_readUint8(self._ptr),
        i16 => sf.c.sfPacket_readInt16(self._ptr),
        u16 => sf.c.sfPacket_readUint16(self._ptr),
        i32 => sf.c.sfPacket_readInt32(self._ptr),
        u32 => sf.c.sfPacket_readUint32(self._ptr),
        f32 => sf.c.sfPacket_readFloat(self._ptr),
        f64 => sf.c.sfPacket_readDouble(self._ptr),
        [*:0]const u8 => sf.c.sfPacket_readString(self._ptr),
        [*:0]const u16 => sf.c.sfPacket_readWideString(self._ptr),
        else => @compileError("Can't read type " ++ @typeName(T) ++ " from packet"),
    };
    try self.checkLastRead();
    return res;
}

/// Writes a value to the packet
/// Slightly faster than using a writer for bigger types
pub fn write(self: *Packet, comptime T: type, value: T) !void {
    // TODO: find how to make this safer
    switch (T) {
        bool => sf.c.sfPacket_writeBool(self._ptr, @boolToInt(value)),
        i8 => sf.c.sfPacket_writeInt8(self._ptr, value),
        u8 => sf.c.sfPacket_writeUint8(self._ptr, value),
        i16 => sf.c.sfPacket_writeInt16(self._ptr, value),
        u16 => sf.c.sfPacket_writeUint16(self._ptr, value),
        i32 => sf.c.sfPacket_writeInt32(self._ptr, value),
        u32 => sf.c.sfPacket_writeUint32(self._ptr, value),
        f32 => sf.c.sfPacket_writeFloat(self._ptr, value),
        f64 => sf.c.sfPacket_writeDouble(self._ptr, value),
        [*:0]const u8 => sf.c.sfPacket_writeString(self._ptr, value),
        [*:0]const u16 => sf.c.sfPacket_writeWideString(self._ptr, value),
        else => @compileError("Can't write type " ++ @typeName(T) ++ " to packet"),
    }
}

/// Writer type for a packet
pub const Writer = std.io.Writer(*Packet, sf.Error, writeFn);
/// Initializes a Writer which will write to the packet
/// Slightly slower than write for bigger types but more convinient for some things
pub fn writer(self: *Packet) Writer {
    return .{ .context = self };
}
/// Write function for the writer
fn writeFn(self: *Packet, m: []const u8) sf.Error!usize {
    // TODO: find out if I can have better safety here
    const size_a = self.getDataSize();
    sf.c.sfPacket_append(self._ptr, m.ptr, m.len);
    const size_b = self.getDataSize();
    const size = size_b - size_a;
    if (m.len != 0 and size == 0)
        return sf.Error.cannotWriteToPacket;
    return size;
}

/// Reader type for a packet
pub const Reader = std.io.Reader(*Packet, sf.Error, readFn);
/// Initializes a Reader which will read the packet's bytes
/// Slightly slower than read for bigger types but more convinient for some things
pub fn reader(self: *Packet) Reader {
    return .{ .context = self };
}
/// Read function for the reader
fn readFn(self: *Packet, b: []u8) sf.Error!usize {
    for (b) |*byte, i| {
        if (sf.c.sfPacket_endOfPacket(self._ptr) != 0)
            return i;
        const val = sf.c.sfPacket_readUint8(self._ptr);
        try self.checkLastRead();
        byte.* = val;
    }
    return b.len;
}

/// Pointer to the csfml structure
_ptr: *sf.c.sfPacket,

test "packet: reading and writing" {
    const tst = std.testing;

    var pack1 = try Packet.create();
    defer pack1.destroy();

    // writing to the packet
    // using its methods
    try pack1.write(u16, 1999);
    try pack1.write(bool, true);
    // using a writer
    {
        var w = pack1.writer();
        try w.writeIntNative(u64, 12345678);
        try w.writeAll("oh:");
    }
    // using append
    const str = "abc";
    try pack1.append(str);
    try tst.expectEqual(@as(usize, 17), pack1.getDataSize());

    var pack2 = try pack1.copy();
    defer pack2.destroy();
    pack1.clear();
    try tst.expectEqual(@as(usize, 0), pack1.getDataSize());
    try tst.expect(pack1.isAtEnd());

    // reading tests
    // read method
    try tst.expectEqual(@as(u16, 1999), try pack2.read(u16));
    try tst.expect(try pack2.read(bool));
    // reader
    {
        var buf: [16]u8 = undefined;
        var r = pack2.reader();
        try tst.expectEqual(@as(u64, 12345678), try r.readIntNative(u64));
        var count = try r.readAll(&buf);
        try tst.expectEqual(@as(usize, 6), count);
        try tst.expectEqualStrings("oh:abc", buf[0..count]);
    }
    // getdata
    const dat = pack2.getData();
    try tst.expectEqual(@as(usize, 17), dat.len);
    try tst.expectEqualStrings("h:a", dat[12..15]);
    try tst.expect(pack2.isAtEnd());
}
