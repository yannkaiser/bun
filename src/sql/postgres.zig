const bun = @import("bun");
const JSC = bun.JSC;
const String = bun.String;
const uws = bun.uws;
const std = @import("std");
pub const debug = bun.Output.scoped(.Postgres, false);
pub const int4 = u32;
pub const PostgresInt32 = int4;
pub const int8 = i64;
pub const PostgresInt64 = int8;
pub const short = u16;
pub const PostgresShort = u16;
const Crypto = JSC.API.Bun.Crypto;
const JSValue = JSC.JSValue;
const BoringSSL = bun.BoringSSL;
pub const AnyPostgresError = error{
    ConnectionClosed,
    ExpectedRequest,
    ExpectedStatement,
    InvalidBackendKeyData,
    InvalidBinaryData,
    InvalidByteSequence,
    InvalidByteSequenceForEncoding,
    InvalidCharacter,
    InvalidMessage,
    InvalidMessageLength,
    InvalidQueryBinding,
    InvalidServerKey,
    InvalidServerSignature,
    JSError,
    MultidimensionalArrayNotSupportedYet,
    NullsInArrayNotSupportedYet,
    OutOfMemory,
    Overflow,
    PBKDFD2,
    SASL_SIGNATURE_MISMATCH,
    SASL_SIGNATURE_INVALID_BASE64,
    ShortRead,
    TLSNotAvailable,
    TLSUpgradeFailed,
    UnexpectedMessage,
    UNKNOWN_AUTHENTICATION_METHOD,
    UNSUPPORTED_AUTHENTICATION_METHOD,
    UnsupportedByteaFormat,
    UnsupportedIntegerSize,
    UnsupportedArrayFormat,
    UnsupportedNumericFormat,
    UnknownFormatCode,
};

pub fn postgresErrorToJS(globalObject: *JSC.JSGlobalObject, message: ?[]const u8, err: AnyPostgresError) JSValue {
    const error_code: JSC.Error = switch (err) {
        error.ConnectionClosed => .POSTGRES_CONNECTION_CLOSED,
        error.ExpectedRequest => .POSTGRES_EXPECTED_REQUEST,
        error.ExpectedStatement => .POSTGRES_EXPECTED_STATEMENT,
        error.InvalidBackendKeyData => .POSTGRES_INVALID_BACKEND_KEY_DATA,
        error.InvalidBinaryData => .POSTGRES_INVALID_BINARY_DATA,
        error.InvalidByteSequence => .POSTGRES_INVALID_BYTE_SEQUENCE,
        error.InvalidByteSequenceForEncoding => .POSTGRES_INVALID_BYTE_SEQUENCE_FOR_ENCODING,
        error.InvalidCharacter => .POSTGRES_INVALID_CHARACTER,
        error.InvalidMessage => .POSTGRES_INVALID_MESSAGE,
        error.InvalidMessageLength => .POSTGRES_INVALID_MESSAGE_LENGTH,
        error.InvalidQueryBinding => .POSTGRES_INVALID_QUERY_BINDING,
        error.InvalidServerKey => .POSTGRES_INVALID_SERVER_KEY,
        error.InvalidServerSignature => .POSTGRES_INVALID_SERVER_SIGNATURE,
        error.MultidimensionalArrayNotSupportedYet => .POSTGRES_MULTIDIMENSIONAL_ARRAY_NOT_SUPPORTED_YET,
        error.NullsInArrayNotSupportedYet => .POSTGRES_NULLS_IN_ARRAY_NOT_SUPPORTED_YET,
        error.Overflow => .POSTGRES_OVERFLOW,
        error.PBKDFD2 => .POSTGRES_AUTHENTICATION_FAILED_PBKDF2,
        error.SASL_SIGNATURE_MISMATCH => .POSTGRES_SASL_SIGNATURE_MISMATCH,
        error.SASL_SIGNATURE_INVALID_BASE64 => .POSTGRES_SASL_SIGNATURE_INVALID_BASE64,
        error.TLSNotAvailable => .POSTGRES_TLS_NOT_AVAILABLE,
        error.TLSUpgradeFailed => .POSTGRES_TLS_UPGRADE_FAILED,
        error.UnexpectedMessage => .POSTGRES_UNEXPECTED_MESSAGE,
        error.UNKNOWN_AUTHENTICATION_METHOD => .POSTGRES_UNKNOWN_AUTHENTICATION_METHOD,
        error.UNSUPPORTED_AUTHENTICATION_METHOD => .POSTGRES_UNSUPPORTED_AUTHENTICATION_METHOD,
        error.UnsupportedByteaFormat => .POSTGRES_UNSUPPORTED_BYTEA_FORMAT,
        error.UnsupportedArrayFormat => .POSTGRES_UNSUPPORTED_ARRAY_FORMAT,
        error.UnsupportedIntegerSize => .POSTGRES_UNSUPPORTED_INTEGER_SIZE,
        error.UnsupportedNumericFormat => .POSTGRES_UNSUPPORTED_NUMERIC_FORMAT,
        error.UnknownFormatCode => .POSTGRES_UNKNOWN_FORMAT_CODE,
        error.JSError => {
            return globalObject.takeException(error.JSError);
        },
        error.OutOfMemory => {
            // TODO: add binding for creating an out of memory error?
            return globalObject.takeException(globalObject.throwOutOfMemory());
        },
        error.ShortRead => {
            bun.unreachablePanic("Assertion failed: ShortRead should be handled by the caller in postgres", .{});
        },
    };
    if (message) |msg| {
        return error_code.fmt(globalObject, "{s}", .{msg});
    }
    return error_code.fmt(globalObject, "Failed to bind query: {s}", .{@errorName(err)});
}

pub const SSLMode = enum(u8) {
    disable = 0,
    prefer = 1,
    require = 2,
    verify_ca = 3,
    verify_full = 4,
};

pub const Data = union(enum) {
    owned: bun.ByteList,
    temporary: []const u8,
    empty: void,

    pub const Empty: Data = .{ .empty = {} };

    pub fn toOwned(this: @This()) !bun.ByteList {
        return switch (this) {
            .owned => this.owned,
            .temporary => bun.ByteList.init(try bun.default_allocator.dupe(u8, this.temporary)),
            .empty => bun.ByteList.init(&.{}),
        };
    }

    pub fn deinit(this: *@This()) void {
        switch (this.*) {
            .owned => this.owned.deinitWithAllocator(bun.default_allocator),
            .temporary => {},
            .empty => {},
        }
    }

    /// Zero bytes before deinit
    /// Generally, for security reasons.
    pub fn zdeinit(this: *@This()) void {
        switch (this.*) {
            .owned => {

                // Zero bytes before deinit
                @memset(this.owned.slice(), 0);

                this.owned.deinitWithAllocator(bun.default_allocator);
            },
            .temporary => {},
            .empty => {},
        }
    }

    pub fn slice(this: @This()) []const u8 {
        return switch (this) {
            .owned => this.owned.slice(),
            .temporary => this.temporary,
            .empty => "",
        };
    }

    pub fn substring(this: @This(), start_index: usize, end_index: usize) Data {
        return switch (this) {
            .owned => .{ .temporary = this.owned.slice()[start_index..end_index] },
            .temporary => .{ .temporary = this.temporary[start_index..end_index] },
            .empty => .{ .empty = {} },
        };
    }

    pub fn sliceZ(this: @This()) [:0]const u8 {
        return switch (this) {
            .owned => this.owned.slice()[0..this.owned.len :0],
            .temporary => this.temporary[0..this.temporary.len :0],
            .empty => "",
        };
    }
};
pub const protocol = @import("./postgres/postgres_protocol.zig");
pub const types = @import("./postgres/postgres_types.zig");

const Socket = uws.AnySocket;
const PreparedStatementsMap = std.HashMapUnmanaged(u64, *PostgresSQLStatement, bun.IdentityContext(u64), 80);

const SocketMonitor = struct {
    const DebugSocketMonitorWriter = struct {
        var file: std.fs.File = undefined;
        var enabled = false;
        var check = std.once(load);
        pub fn write(data: []const u8) void {
            file.writeAll(data) catch {};
        }

        fn load() void {
            if (bun.getenvZAnyCase("BUN_POSTGRES_SOCKET_MONITOR")) |monitor| {
                enabled = true;
                file = std.fs.cwd().createFile(monitor, .{ .truncate = true }) catch {
                    enabled = false;
                    return;
                };
                debug("writing to {s}", .{monitor});
            }
        }
    };

    const DebugSocketMonitorReader = struct {
        var file: std.fs.File = undefined;
        var enabled = false;
        var check = std.once(load);

        fn load() void {
            if (bun.getenvZAnyCase("BUN_POSTGRES_SOCKET_MONITOR_READER")) |monitor| {
                enabled = true;
                file = std.fs.cwd().createFile(monitor, .{ .truncate = true }) catch {
                    enabled = false;
                    return;
                };
                debug("duplicating reads to {s}", .{monitor});
            }
        }

        pub fn write(data: []const u8) void {
            file.writeAll(data) catch {};
        }
    };

    pub fn write(data: []const u8) void {
        if (comptime bun.Environment.isDebug) {
            DebugSocketMonitorWriter.check.call();
            if (DebugSocketMonitorWriter.enabled) {
                DebugSocketMonitorWriter.write(data);
            }
        }
    }

    pub fn read(data: []const u8) void {
        if (comptime bun.Environment.isDebug) {
            DebugSocketMonitorReader.check.call();
            if (DebugSocketMonitorReader.enabled) {
                DebugSocketMonitorReader.write(data);
            }
        }
    }
};

pub const PostgresSQLContext = struct {
    tcp: ?*uws.SocketContext = null,

    onQueryResolveFn: JSC.Strong.Optional = .empty,
    onQueryRejectFn: JSC.Strong.Optional = .empty,

    pub fn init(globalObject: *JSC.JSGlobalObject, callframe: *JSC.CallFrame) bun.JSError!JSC.JSValue {
        var ctx = &globalObject.bunVM().rareData().postgresql_context;
        ctx.onQueryResolveFn.set(globalObject, callframe.argument(0));
        ctx.onQueryRejectFn.set(globalObject, callframe.argument(1));

        return .js_undefined;
    }

    comptime {
        const js_init = JSC.toJSHostFn(init);
        @export(&js_init, .{ .name = "PostgresSQLContext__init" });
    }
};
pub const PostgresSQLQueryResultMode = enum(u2) {
    objects = 0,
    values = 1,
    raw = 2,
};

const JSRef = JSC.JSRef;

pub const PostgresSQLQuery = struct {
    statement: ?*PostgresSQLStatement = null,
    query: bun.String = bun.String.empty,
    cursor_name: bun.String = bun.String.empty,

    thisValue: JSRef = JSRef.empty(),

    status: Status = Status.pending,

    ref_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(1),

    flags: packed struct(u8) {
        is_done: bool = false,
        binary: bool = false,
        bigint: bool = false,
        simple: bool = false,
        result_mode: PostgresSQLQueryResultMode = .objects,
        _padding: u2 = 0,
    } = .{},

    pub const js = JSC.Codegen.JSPostgresSQLQuery;
    pub const toJS = js.toJS;
    pub const fromJS = js.fromJS;
    pub const fromJSDirect = js.fromJSDirect;

    pub fn getTarget(this: *PostgresSQLQuery, globalObject: *JSC.JSGlobalObject, clean_target: bool) JSC.JSValue {
        const thisValue = this.thisValue.get();
        if (thisValue == .zero) {
            return .zero;
        }
        const target = js.targetGetCached(thisValue) orelse return .zero;
        if (clean_target) {
            js.targetSetCached(thisValue, globalObject, .zero);
        }
        return target;
    }

    pub const Status = enum(u8) {
        /// The query was just enqueued, statement status can be checked for more details
        pending,
        /// The query is being bound to the statement
        binding,
        /// The query is running
        running,
        /// The query is waiting for a partial response
        partial_response,
        /// The query was successful
        success,
        /// The query failed
        fail,

        pub fn isRunning(this: Status) bool {
            return @intFromEnum(this) > @intFromEnum(Status.pending) and @intFromEnum(this) < @intFromEnum(Status.success);
        }
    };

    pub fn hasPendingActivity(this: *@This()) bool {
        return this.ref_count.load(.monotonic) > 1;
    }

    pub fn deinit(this: *@This()) void {
        this.thisValue.deinit();
        if (this.statement) |statement| {
            statement.deref();
        }
        this.query.deref();
        this.cursor_name.deref();
        bun.default_allocator.destroy(this);
    }

    pub fn finalize(this: *@This()) void {
        debug("PostgresSQLQuery finalize", .{});
        if (this.thisValue == .weak) {
            // clean up if is a weak reference, if is a strong reference we need to wait until the query is done
            // if we are a strong reference, here is probably a bug because GC'd should not happen
            this.thisValue.weak = .zero;
        }
        this.deref();
    }

    pub fn deref(this: *@This()) void {
        const ref_count = this.ref_count.fetchSub(1, .monotonic);

        if (ref_count == 1) {
            this.deinit();
        }
    }

    pub fn ref(this: *@This()) void {
        bun.assert(this.ref_count.fetchAdd(1, .monotonic) > 0);
    }

    pub fn onWriteFail(
        this: *@This(),
        err: AnyPostgresError,
        globalObject: *JSC.JSGlobalObject,
        queries_array: JSValue,
    ) void {
        this.status = .fail;
        const thisValue = this.thisValue.get();
        defer this.thisValue.deinit();
        const targetValue = this.getTarget(globalObject, true);
        if (thisValue == .zero or targetValue == .zero) {
            return;
        }

        const vm = JSC.VirtualMachine.get();
        const function = vm.rareData().postgresql_context.onQueryRejectFn.get().?;
        const event_loop = vm.eventLoop();
        event_loop.runCallback(function, globalObject, thisValue, &.{
            targetValue,
            postgresErrorToJS(globalObject, null, err),
            queries_array,
        });
    }
    pub fn onJSError(this: *@This(), err: JSC.JSValue, globalObject: *JSC.JSGlobalObject) void {
        this.status = .fail;
        this.ref();
        defer this.deref();

        const thisValue = this.thisValue.get();
        defer this.thisValue.deinit();
        const targetValue = this.getTarget(globalObject, true);
        if (thisValue == .zero or targetValue == .zero) {
            return;
        }

        var vm = JSC.VirtualMachine.get();
        const function = vm.rareData().postgresql_context.onQueryRejectFn.get().?;
        const event_loop = vm.eventLoop();
        event_loop.runCallback(function, globalObject, thisValue, &.{
            targetValue,
            err,
        });
    }
    pub fn onError(this: *@This(), err: PostgresSQLStatement.Error, globalObject: *JSC.JSGlobalObject) void {
        this.onJSError(err.toJS(globalObject), globalObject);
    }

    const CommandTag = union(enum) {
        // For an INSERT command, the tag is INSERT oid rows, where rows is the
        // number of rows inserted. oid used to be the object ID of the inserted
        // row if rows was 1 and the target table had OIDs, but OIDs system
        // columns are not supported anymore; therefore oid is always 0.
        INSERT: u64,
        // For a DELETE command, the tag is DELETE rows where rows is the number
        // of rows deleted.
        DELETE: u64,
        // For an UPDATE command, the tag is UPDATE rows where rows is the
        // number of rows updated.
        UPDATE: u64,
        // For a MERGE command, the tag is MERGE rows where rows is the number
        // of rows inserted, updated, or deleted.
        MERGE: u64,
        // For a SELECT or CREATE TABLE AS command, the tag is SELECT rows where
        // rows is the number of rows retrieved.
        SELECT: u64,
        // For a MOVE command, the tag is MOVE rows where rows is the number of
        // rows the cursor's position has been changed by.
        MOVE: u64,
        // For a FETCH command, the tag is FETCH rows where rows is the number
        // of rows that have been retrieved from the cursor.
        FETCH: u64,
        // For a COPY command, the tag is COPY rows where rows is the number of
        // rows copied. (Note: the row count appears only in PostgreSQL 8.2 and
        // later.)
        COPY: u64,

        other: []const u8,

        pub fn toJSTag(this: CommandTag, globalObject: *JSC.JSGlobalObject) JSValue {
            return switch (this) {
                .INSERT => JSValue.jsNumber(1),
                .DELETE => JSValue.jsNumber(2),
                .UPDATE => JSValue.jsNumber(3),
                .MERGE => JSValue.jsNumber(4),
                .SELECT => JSValue.jsNumber(5),
                .MOVE => JSValue.jsNumber(6),
                .FETCH => JSValue.jsNumber(7),
                .COPY => JSValue.jsNumber(8),
                .other => |tag| JSC.ZigString.init(tag).toJS(globalObject),
            };
        }

        pub fn toJSNumber(this: CommandTag) JSValue {
            return switch (this) {
                .other => JSValue.jsNumber(0),
                inline else => |val| JSValue.jsNumber(val),
            };
        }

        const KnownCommand = enum {
            INSERT,
            DELETE,
            UPDATE,
            MERGE,
            SELECT,
            MOVE,
            FETCH,
            COPY,

            pub const Map = bun.ComptimeEnumMap(KnownCommand);
        };

        pub fn init(tag: []const u8) CommandTag {
            const first_space_index = bun.strings.indexOfChar(tag, ' ') orelse return .{ .other = tag };
            const cmd = KnownCommand.Map.get(tag[0..first_space_index]) orelse return .{
                .other = tag,
            };

            const number = brk: {
                switch (cmd) {
                    .INSERT => {
                        var remaining = tag[@min(first_space_index + 1, tag.len)..];
                        const second_space = bun.strings.indexOfChar(remaining, ' ') orelse return .{ .other = tag };
                        remaining = remaining[@min(second_space + 1, remaining.len)..];
                        break :brk std.fmt.parseInt(u64, remaining, 0) catch |err| {
                            debug("CommandTag failed to parse number: {s}", .{@errorName(err)});
                            return .{ .other = tag };
                        };
                    },
                    else => {
                        const after_tag = tag[@min(first_space_index + 1, tag.len)..];
                        break :brk std.fmt.parseInt(u64, after_tag, 0) catch |err| {
                            debug("CommandTag failed to parse number: {s}", .{@errorName(err)});
                            return .{ .other = tag };
                        };
                    },
                }
            };

            switch (cmd) {
                inline else => |t| return @unionInit(CommandTag, @tagName(t), number),
            }
        }
    };

    pub fn allowGC(thisValue: JSC.JSValue, globalObject: *JSC.JSGlobalObject) void {
        if (thisValue == .zero) {
            return;
        }

        defer thisValue.ensureStillAlive();
        js.bindingSetCached(thisValue, globalObject, .zero);
        js.pendingValueSetCached(thisValue, globalObject, .zero);
        js.targetSetCached(thisValue, globalObject, .zero);
    }

    fn consumePendingValue(thisValue: JSC.JSValue, globalObject: *JSC.JSGlobalObject) ?JSValue {
        const pending_value = js.pendingValueGetCached(thisValue) orelse return null;
        js.pendingValueSetCached(thisValue, globalObject, .zero);
        return pending_value;
    }

    pub fn onResult(this: *@This(), command_tag_str: []const u8, globalObject: *JSC.JSGlobalObject, connection: JSC.JSValue, is_last: bool) void {
        this.ref();
        defer this.deref();

        const thisValue = this.thisValue.get();
        const targetValue = this.getTarget(globalObject, is_last);
        if (is_last) {
            this.status = .success;
        } else {
            this.status = .partial_response;
        }
        defer if (is_last) {
            allowGC(thisValue, globalObject);
            this.thisValue.deinit();
        };
        if (thisValue == .zero or targetValue == .zero) {
            return;
        }

        const vm = JSC.VirtualMachine.get();
        const function = vm.rareData().postgresql_context.onQueryResolveFn.get().?;
        const event_loop = vm.eventLoop();
        const tag = CommandTag.init(command_tag_str);

        event_loop.runCallback(function, globalObject, thisValue, &.{
            targetValue,
            consumePendingValue(thisValue, globalObject) orelse .js_undefined,
            tag.toJSTag(globalObject),
            tag.toJSNumber(),
            if (connection == .zero) .js_undefined else PostgresSQLConnection.js.queriesGetCached(connection) orelse .js_undefined,
            JSValue.jsBoolean(is_last),
        });
    }

    pub fn constructor(globalThis: *JSC.JSGlobalObject, callframe: *JSC.CallFrame) bun.JSError!*PostgresSQLQuery {
        _ = callframe;
        return globalThis.throw("PostgresSQLQuery cannot be constructed directly", .{});
    }

    pub fn estimatedSize(this: *PostgresSQLQuery) usize {
        _ = this;
        return @sizeOf(PostgresSQLQuery);
    }

    pub fn call(globalThis: *JSC.JSGlobalObject, callframe: *JSC.CallFrame) bun.JSError!JSC.JSValue {
        const arguments = callframe.arguments_old(6).slice();
        var args = JSC.CallFrame.ArgumentsSlice.init(globalThis.bunVM(), arguments);
        defer args.deinit();
        const query = args.nextEat() orelse {
            return globalThis.throw("query must be a string", .{});
        };
        const values = args.nextEat() orelse {
            return globalThis.throw("values must be an array", .{});
        };

        if (!query.isString()) {
            return globalThis.throw("query must be a string", .{});
        }

        if (values.jsType() != .Array) {
            return globalThis.throw("values must be an array", .{});
        }

        const pending_value: JSValue = args.nextEat() orelse .js_undefined;
        const columns: JSValue = args.nextEat() orelse .js_undefined;
        const js_bigint: JSValue = args.nextEat() orelse .false;
        const js_simple: JSValue = args.nextEat() orelse .false;

        const bigint = js_bigint.isBoolean() and js_bigint.asBoolean();
        const simple = js_simple.isBoolean() and js_simple.asBoolean();
        if (simple) {
            if (try values.getLength(globalThis) > 0) {
                return globalThis.throwInvalidArguments("simple query cannot have parameters", .{});
            }
            if (try query.getLength(globalThis) >= std.math.maxInt(i32)) {
                return globalThis.throwInvalidArguments("query is too long", .{});
            }
        }
        if (!pending_value.jsType().isArrayLike()) {
            return globalThis.throwInvalidArgumentType("query", "pendingValue", "Array");
        }

        var ptr = try bun.default_allocator.create(PostgresSQLQuery);

        const this_value = ptr.toJS(globalThis);
        this_value.ensureStillAlive();

        ptr.* = .{
            .query = try query.toBunString(globalThis),
            .thisValue = JSRef.initWeak(this_value),
            .flags = .{
                .bigint = bigint,
                .simple = simple,
            },
        };

        js.bindingSetCached(this_value, globalThis, values);
        js.pendingValueSetCached(this_value, globalThis, pending_value);
        if (!columns.isUndefined()) {
            js.columnsSetCached(this_value, globalThis, columns);
        }

        return this_value;
    }

    pub fn push(this: *PostgresSQLQuery, globalThis: *JSC.JSGlobalObject, value: JSValue) void {
        var pending_value = this.pending_value.get() orelse return;
        pending_value.push(globalThis, value);
    }

    pub fn doDone(this: *@This(), globalObject: *JSC.JSGlobalObject, _: *JSC.CallFrame) bun.JSError!JSValue {
        _ = globalObject;
        this.flags.is_done = true;
        return .js_undefined;
    }
    pub fn setPendingValue(this: *PostgresSQLQuery, globalObject: *JSC.JSGlobalObject, callframe: *JSC.CallFrame) bun.JSError!JSValue {
        const result = callframe.argument(0);
        js.pendingValueSetCached(this.thisValue.get(), globalObject, result);
        return .js_undefined;
    }
    pub fn setMode(this: *PostgresSQLQuery, globalObject: *JSC.JSGlobalObject, callframe: *JSC.CallFrame) bun.JSError!JSValue {
        const js_mode = callframe.argument(0);
        if (js_mode.isEmptyOrUndefinedOrNull() or !js_mode.isNumber()) {
            return globalObject.throwInvalidArgumentType("setMode", "mode", "Number");
        }

        const mode = js_mode.coerce(i32, globalObject);
        this.flags.result_mode = std.meta.intToEnum(PostgresSQLQueryResultMode, mode) catch {
            return globalObject.throwInvalidArgumentTypeValue("mode", "Number", js_mode);
        };
        return .js_undefined;
    }

    pub fn doRun(this: *PostgresSQLQuery, globalObject: *JSC.JSGlobalObject, callframe: *JSC.CallFrame) bun.JSError!JSValue {
        var arguments_ = callframe.arguments_old(2);
        const arguments = arguments_.slice();
        const connection: *PostgresSQLConnection = arguments[0].as(PostgresSQLConnection) orelse {
            return globalObject.throw("connection must be a PostgresSQLConnection", .{});
        };

        connection.poll_ref.ref(globalObject.bunVM());
        var query = arguments[1];

        if (!query.isObject()) {
            return globalObject.throwInvalidArgumentType("run", "query", "Query");
        }

        const this_value = callframe.this();
        const binding_value = js.bindingGetCached(this_value) orelse .zero;
        var query_str = this.query.toUTF8(bun.default_allocator);
        defer query_str.deinit();
        var writer = connection.writer();

        if (this.flags.simple) {
            debug("executeQuery", .{});

            const can_execute = !connection.hasQueryRunning();
            if (can_execute) {
                PostgresRequest.executeQuery(query_str.slice(), PostgresSQLConnection.Writer, writer) catch |err| {
                    if (!globalObject.hasException())
                        return globalObject.throwValue(postgresErrorToJS(globalObject, "failed to execute query", err));
                    return error.JSError;
                };
                connection.flags.is_ready_for_query = false;
                this.status = .running;
            } else {
                this.status = .pending;
            }
            const stmt = bun.default_allocator.create(PostgresSQLStatement) catch {
                return globalObject.throwOutOfMemory();
            };
            // Query is simple and it's the only owner of the statement
            stmt.* = .{
                .signature = Signature.empty(),
                .ref_count = 1,
                .status = .parsing,
            };
            this.statement = stmt;
            // We need a strong reference to the query so that it doesn't get GC'd
            connection.requests.writeItem(this) catch return globalObject.throwOutOfMemory();
            this.ref();
            this.thisValue.upgrade(globalObject);

            js.targetSetCached(this_value, globalObject, query);
            if (this.status == .running) {
                connection.flushDataAndResetTimeout();
            } else {
                connection.resetConnectionTimeout();
            }
            return .js_undefined;
        }

        const columns_value: JSValue = js.columnsGetCached(this_value) orelse .js_undefined;

        var signature = Signature.generate(globalObject, query_str.slice(), binding_value, columns_value, connection.prepared_statement_id, connection.flags.use_unnamed_prepared_statements) catch |err| {
            if (!globalObject.hasException())
                return globalObject.throwError(err, "failed to generate signature");
            return error.JSError;
        };

        const has_params = signature.fields.len > 0;
        var did_write = false;
        enqueue: {
            var connection_entry_value: ?**PostgresSQLStatement = null;
            if (!connection.flags.use_unnamed_prepared_statements) {
                const entry = connection.statements.getOrPut(bun.default_allocator, bun.hash(signature.name)) catch |err| {
                    signature.deinit();
                    return globalObject.throwError(err, "failed to allocate statement");
                };
                connection_entry_value = entry.value_ptr;
                if (entry.found_existing) {
                    this.statement = connection_entry_value.?.*;
                    this.statement.?.ref();
                    signature.deinit();

                    switch (this.statement.?.status) {
                        .failed => {
                            // If the statement failed, we need to throw the error
                            return globalObject.throwValue(this.statement.?.error_response.?.toJS(globalObject));
                        },
                        .prepared => {
                            if (!connection.hasQueryRunning()) {
                                this.flags.binary = this.statement.?.fields.len > 0;
                                debug("bindAndExecute", .{});

                                // bindAndExecute will bind + execute, it will change to running after binding is complete
                                PostgresRequest.bindAndExecute(globalObject, this.statement.?, binding_value, columns_value, PostgresSQLConnection.Writer, writer) catch |err| {
                                    if (!globalObject.hasException())
                                        return globalObject.throwValue(postgresErrorToJS(globalObject, "failed to bind and execute query", err));
                                    return error.JSError;
                                };
                                connection.flags.is_ready_for_query = false;
                                this.status = .binding;

                                did_write = true;
                            }
                        },
                        .parsing, .pending => {},
                    }

                    break :enqueue;
                }
            }
            const can_execute = !connection.hasQueryRunning();

            if (can_execute) {
                // If it does not have params, we can write and execute immediately in one go
                if (!has_params) {
                    debug("prepareAndQueryWithSignature", .{});
                    // prepareAndQueryWithSignature will write + bind + execute, it will change to running after binding is complete
                    PostgresRequest.prepareAndQueryWithSignature(globalObject, query_str.slice(), binding_value, PostgresSQLConnection.Writer, writer, &signature) catch |err| {
                        signature.deinit();
                        if (!globalObject.hasException())
                            return globalObject.throwValue(postgresErrorToJS(globalObject, "failed to prepare and query", err));
                        return error.JSError;
                    };
                    connection.flags.is_ready_for_query = false;
                    this.status = .binding;
                    did_write = true;
                } else {
                    debug("writeQuery", .{});

                    PostgresRequest.writeQuery(query_str.slice(), signature.prepared_statement_name, signature.fields, PostgresSQLConnection.Writer, writer) catch |err| {
                        signature.deinit();
                        if (!globalObject.hasException())
                            return globalObject.throwValue(postgresErrorToJS(globalObject, "failed to write query", err));
                        return error.JSError;
                    };
                    writer.write(&protocol.Sync) catch |err| {
                        signature.deinit();
                        if (!globalObject.hasException())
                            return globalObject.throwValue(postgresErrorToJS(globalObject, "failed to flush", err));
                        return error.JSError;
                    };
                    connection.flags.is_ready_for_query = false;
                    did_write = true;
                }
            }
            {
                const stmt = bun.default_allocator.create(PostgresSQLStatement) catch {
                    return globalObject.throwOutOfMemory();
                };
                // we only have connection_entry_value if we are using named prepared statements
                if (connection_entry_value) |entry_value| {
                    connection.prepared_statement_id += 1;
                    stmt.* = .{ .signature = signature, .ref_count = 2, .status = if (can_execute) .parsing else .pending };
                    this.statement = stmt;

                    entry_value.* = stmt;
                } else {
                    stmt.* = .{ .signature = signature, .ref_count = 1, .status = if (can_execute) .parsing else .pending };
                    this.statement = stmt;
                }
            }
        }
        // We need a strong reference to the query so that it doesn't get GC'd
        connection.requests.writeItem(this) catch return globalObject.throwOutOfMemory();
        this.ref();
        this.thisValue.upgrade(globalObject);

        js.targetSetCached(this_value, globalObject, query);
        if (did_write) {
            connection.flushDataAndResetTimeout();
        } else {
            connection.resetConnectionTimeout();
        }
        return .js_undefined;
    }

    pub fn doCancel(this: *PostgresSQLQuery, globalObject: *JSC.JSGlobalObject, callframe: *JSC.CallFrame) bun.JSError!JSValue {
        _ = callframe;
        _ = globalObject;
        _ = this;

        return .js_undefined;
    }

    comptime {
        const jscall = JSC.toJSHostFn(call);
        @export(&jscall, .{ .name = "PostgresSQLQuery__createInstance" });
    }
};

pub const PostgresRequest = struct {
    pub fn writeBind(
        name: []const u8,
        cursor_name: bun.String,
        globalObject: *JSC.JSGlobalObject,
        values_array: JSValue,
        columns_value: JSValue,
        parameter_fields: []const int4,
        result_fields: []const protocol.FieldDescription,
        comptime Context: type,
        writer: protocol.NewWriter(Context),
    ) !void {
        try writer.write("B");
        const length = try writer.length();

        try writer.String(cursor_name);
        try writer.string(name);

        const len: u32 = @truncate(parameter_fields.len);

        // The number of parameter format codes that follow (denoted C
        // below). This can be zero to indicate that there are no
        // parameters or that the parameters all use the default format
        // (text); or one, in which case the specified format code is
        // applied to all parameters; or it can equal the actual number
        // of parameters.
        try writer.short(len);

        var iter = try QueryBindingIterator.init(values_array, columns_value, globalObject);
        for (0..len) |i| {
            const parameter_field = parameter_fields[i];
            const is_custom_type = std.math.maxInt(short) < parameter_field;
            const tag: types.Tag = if (is_custom_type) .text else @enumFromInt(@as(short, @intCast(parameter_field)));

            const force_text = is_custom_type or (tag.isBinaryFormatSupported() and brk: {
                iter.to(@truncate(i));
                if (try iter.next()) |value| {
                    break :brk value.isString();
                }
                if (iter.anyFailed()) {
                    return error.InvalidQueryBinding;
                }
                break :brk false;
            });

            if (force_text) {
                // If they pass a value as a string, let's avoid attempting to
                // convert it to the binary representation. This minimizes the room
                // for mistakes on our end, such as stripping the timezone
                // differently than what Postgres does when given a timestamp with
                // timezone.
                try writer.short(0);
                continue;
            }

            try writer.short(
                tag.formatCode(),
            );
        }

        // The number of parameter values that follow (possibly zero). This
        // must match the number of parameters needed by the query.
        try writer.short(len);

        debug("Bind: {} ({d} args)", .{ bun.fmt.quote(name), len });
        iter.to(0);
        var i: usize = 0;
        while (try iter.next()) |value| : (i += 1) {
            const tag: types.Tag = brk: {
                if (i >= len) {
                    // parameter in array but not in parameter_fields
                    // this is probably a bug a bug in bun lets return .text here so the server will send a error 08P01
                    // with will describe better the error saying exactly how many parameters are missing and are expected
                    // Example:
                    // SQL error: PostgresError: bind message supplies 0 parameters, but prepared statement "PSELECT * FROM test_table WHERE id=$1 .in$0" requires 1
                    // errno: "08P01",
                    // code: "ERR_POSTGRES_SERVER_ERROR"
                    break :brk .text;
                }
                const parameter_field = parameter_fields[i];
                const is_custom_type = std.math.maxInt(short) < parameter_field;
                break :brk if (is_custom_type) .text else @enumFromInt(@as(short, @intCast(parameter_field)));
            };
            if (value.isEmptyOrUndefinedOrNull()) {
                debug("  -> NULL", .{});
                //  As a special case, -1 indicates a
                // NULL parameter value. No value bytes follow in the NULL case.
                try writer.int4(@bitCast(@as(i32, -1)));
                continue;
            }
            if (comptime bun.Environment.enable_logs) {
                debug("  -> {s}", .{tag.tagName() orelse "(unknown)"});
            }

            switch (
            // If they pass a value as a string, let's avoid attempting to
            // convert it to the binary representation. This minimizes the room
            // for mistakes on our end, such as stripping the timezone
            // differently than what Postgres does when given a timestamp with
            // timezone.
            if (tag.isBinaryFormatSupported() and value.isString()) .text else tag) {
                .jsonb, .json => {
                    var str = bun.String.empty;
                    defer str.deref();
                    value.jsonStringify(globalObject, 0, &str);
                    const slice = str.toUTF8WithoutRef(bun.default_allocator);
                    defer slice.deinit();
                    const l = try writer.length();
                    try writer.write(slice.slice());
                    try l.writeExcludingSelf();
                },
                .bool => {
                    const l = try writer.length();
                    try writer.write(&[1]u8{@intFromBool(value.toBoolean())});
                    try l.writeExcludingSelf();
                },
                .timestamp, .timestamptz => {
                    const l = try writer.length();
                    try writer.int8(types.date.fromJS(globalObject, value));
                    try l.writeExcludingSelf();
                },
                .bytea => {
                    var bytes: []const u8 = "";
                    if (value.asArrayBuffer(globalObject)) |buf| {
                        bytes = buf.byteSlice();
                    }
                    const l = try writer.length();
                    debug("    {d} bytes", .{bytes.len});

                    try writer.write(bytes);
                    try l.writeExcludingSelf();
                },
                .int4 => {
                    const l = try writer.length();
                    try writer.int4(@bitCast(value.coerceToInt32(globalObject)));
                    try l.writeExcludingSelf();
                },
                .int4_array => {
                    const l = try writer.length();
                    try writer.int4(@bitCast(value.coerceToInt32(globalObject)));
                    try l.writeExcludingSelf();
                },
                .float8 => {
                    const l = try writer.length();
                    try writer.f64(@bitCast(try value.toNumber(globalObject)));
                    try l.writeExcludingSelf();
                },

                else => {
                    const str = try String.fromJS(value, globalObject);
                    if (str.tag == .Dead) return error.OutOfMemory;
                    defer str.deref();
                    const slice = str.toUTF8WithoutRef(bun.default_allocator);
                    defer slice.deinit();
                    const l = try writer.length();
                    try writer.write(slice.slice());
                    try l.writeExcludingSelf();
                },
            }
        }

        var any_non_text_fields: bool = false;
        for (result_fields) |field| {
            if (field.typeTag().isBinaryFormatSupported()) {
                any_non_text_fields = true;
                break;
            }
        }

        if (any_non_text_fields) {
            try writer.short(result_fields.len);
            for (result_fields) |field| {
                try writer.short(
                    field.typeTag().formatCode(),
                );
            }
        } else {
            try writer.short(0);
        }

        try length.write();
    }

    pub fn writeQuery(
        query: []const u8,
        name: []const u8,
        params: []const int4,
        comptime Context: type,
        writer: protocol.NewWriter(Context),
    ) AnyPostgresError!void {
        {
            var q = protocol.Parse{
                .name = name,
                .params = params,
                .query = query,
            };
            try q.writeInternal(Context, writer);
            debug("Parse: {}", .{bun.fmt.quote(query)});
        }

        {
            var d = protocol.Describe{
                .p = .{
                    .prepared_statement = name,
                },
            };
            try d.writeInternal(Context, writer);
            debug("Describe: {}", .{bun.fmt.quote(name)});
        }
    }

    pub fn prepareAndQueryWithSignature(
        globalObject: *JSC.JSGlobalObject,
        query: []const u8,
        array_value: JSValue,
        comptime Context: type,
        writer: protocol.NewWriter(Context),
        signature: *Signature,
    ) AnyPostgresError!void {
        try writeQuery(query, signature.prepared_statement_name, signature.fields, Context, writer);
        try writeBind(signature.prepared_statement_name, bun.String.empty, globalObject, array_value, .zero, &.{}, &.{}, Context, writer);
        var exec = protocol.Execute{
            .p = .{
                .prepared_statement = signature.prepared_statement_name,
            },
        };
        try exec.writeInternal(Context, writer);

        try writer.write(&protocol.Flush);
        try writer.write(&protocol.Sync);
    }

    pub fn bindAndExecute(
        globalObject: *JSC.JSGlobalObject,
        statement: *PostgresSQLStatement,
        array_value: JSValue,
        columns_value: JSValue,
        comptime Context: type,
        writer: protocol.NewWriter(Context),
    ) !void {
        try writeBind(statement.signature.prepared_statement_name, bun.String.empty, globalObject, array_value, columns_value, statement.parameters, statement.fields, Context, writer);
        var exec = protocol.Execute{
            .p = .{
                .prepared_statement = statement.signature.prepared_statement_name,
            },
        };
        try exec.writeInternal(Context, writer);

        try writer.write(&protocol.Flush);
        try writer.write(&protocol.Sync);
    }

    pub fn executeQuery(
        query: []const u8,
        comptime Context: type,
        writer: protocol.NewWriter(Context),
    ) !void {
        try protocol.writeQuery(query, Context, writer);
        try writer.write(&protocol.Flush);
        try writer.write(&protocol.Sync);
    }

    pub fn onData(
        connection: *PostgresSQLConnection,
        comptime Context: type,
        reader: protocol.NewReader(Context),
    ) !void {
        while (true) {
            reader.markMessageStart();
            const c = try reader.int(u8);
            debug("read: {c}", .{c});
            switch (c) {
                'D' => try connection.on(.DataRow, Context, reader),
                'd' => try connection.on(.CopyData, Context, reader),
                'S' => {
                    if (connection.tls_status == .message_sent) {
                        bun.debugAssert(connection.tls_status.message_sent == 8);
                        connection.tls_status = .ssl_ok;
                        connection.setupTLS();
                        return;
                    }

                    try connection.on(.ParameterStatus, Context, reader);
                },
                'Z' => try connection.on(.ReadyForQuery, Context, reader),
                'C' => try connection.on(.CommandComplete, Context, reader),
                '2' => try connection.on(.BindComplete, Context, reader),
                '1' => try connection.on(.ParseComplete, Context, reader),
                't' => try connection.on(.ParameterDescription, Context, reader),
                'T' => try connection.on(.RowDescription, Context, reader),
                'R' => try connection.on(.Authentication, Context, reader),
                'n' => try connection.on(.NoData, Context, reader),
                'K' => try connection.on(.BackendKeyData, Context, reader),
                'E' => try connection.on(.ErrorResponse, Context, reader),
                's' => try connection.on(.PortalSuspended, Context, reader),
                '3' => try connection.on(.CloseComplete, Context, reader),
                'G' => try connection.on(.CopyInResponse, Context, reader),
                'N' => {
                    if (connection.tls_status == .message_sent) {
                        connection.tls_status = .ssl_not_available;
                        debug("Server does not support SSL", .{});
                        if (connection.ssl_mode == .require) {
                            connection.fail("Server does not support SSL", error.TLSNotAvailable);
                            return;
                        }
                        continue;
                    }

                    try connection.on(.NoticeResponse, Context, reader);
                },
                'I' => try connection.on(.EmptyQueryResponse, Context, reader),
                'H' => try connection.on(.CopyOutResponse, Context, reader),
                'c' => try connection.on(.CopyDone, Context, reader),
                'W' => try connection.on(.CopyBothResponse, Context, reader),

                else => {
                    debug("Unknown message: {c}", .{c});
                    const to_skip = try reader.length() -| 1;
                    debug("to_skip: {d}", .{to_skip});
                    try reader.skip(@intCast(@max(to_skip, 0)));
                },
            }
        }
    }

    pub const Queue = std.fifo.LinearFifo(*PostgresSQLQuery, .Dynamic);
};

pub const PostgresSQLConnection = struct {
    socket: Socket,
    status: Status = Status.connecting,
    ref_count: u32 = 1,

    write_buffer: bun.OffsetByteList = .{},
    read_buffer: bun.OffsetByteList = .{},
    last_message_start: u32 = 0,
    requests: PostgresRequest.Queue,

    poll_ref: bun.Async.KeepAlive = .{},
    globalObject: *JSC.JSGlobalObject,

    statements: PreparedStatementsMap,
    prepared_statement_id: u64 = 0,
    pending_activity_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    js_value: JSValue = .js_undefined,

    backend_parameters: bun.StringMap = bun.StringMap.init(bun.default_allocator, true),
    backend_key_data: protocol.BackendKeyData = .{},

    database: []const u8 = "",
    user: []const u8 = "",
    password: []const u8 = "",
    path: []const u8 = "",
    options: []const u8 = "",
    options_buf: []const u8 = "",

    authentication_state: AuthenticationState = .{ .pending = {} },

    tls_ctx: ?*uws.SocketContext = null,
    tls_config: JSC.API.ServerConfig.SSLConfig = .{},
    tls_status: TLSStatus = .none,
    ssl_mode: SSLMode = .disable,

    idle_timeout_interval_ms: u32 = 0,
    connection_timeout_ms: u32 = 0,

    flags: ConnectionFlags = .{},

    /// Before being connected, this is a connection timeout timer.
    /// After being connected, this is an idle timeout timer.
    timer: bun.api.Timer.EventLoopTimer = .{
        .tag = .PostgresSQLConnectionTimeout,
        .next = .{
            .sec = 0,
            .nsec = 0,
        },
    },

    /// This timer controls the maximum lifetime of a connection.
    /// It starts when the connection successfully starts (i.e. after handshake is complete).
    /// It stops when the connection is closed.
    max_lifetime_interval_ms: u32 = 0,
    max_lifetime_timer: bun.api.Timer.EventLoopTimer = .{
        .tag = .PostgresSQLConnectionMaxLifetime,
        .next = .{
            .sec = 0,
            .nsec = 0,
        },
    },

    pub const ConnectionFlags = packed struct {
        is_ready_for_query: bool = false,
        is_processing_data: bool = false,
        use_unnamed_prepared_statements: bool = false,
    };

    pub const TLSStatus = union(enum) {
        none,
        pending,

        /// Number of bytes sent of the 8-byte SSL request message.
        /// Since we may send a partial message, we need to know how many bytes were sent.
        message_sent: u8,

        ssl_not_available,
        ssl_ok,
    };

    pub const AuthenticationState = union(enum) {
        pending: void,
        none: void,
        ok: void,
        SASL: SASL,
        md5: void,

        pub fn zero(this: *AuthenticationState) void {
            switch (this.*) {
                .SASL => |*sasl| {
                    sasl.deinit();
                },
                else => {},
            }
            this.* = .{ .none = {} };
        }
    };

    pub const SASL = struct {
        const nonce_byte_len = 18;
        const nonce_base64_len = bun.base64.encodeLenFromSize(nonce_byte_len);

        const server_signature_byte_len = 32;
        const server_signature_base64_len = bun.base64.encodeLenFromSize(server_signature_byte_len);

        const salted_password_byte_len = 32;

        nonce_base64_bytes: [nonce_base64_len]u8 = .{0} ** nonce_base64_len,
        nonce_len: u8 = 0,

        server_signature_base64_bytes: [server_signature_base64_len]u8 = .{0} ** server_signature_base64_len,
        server_signature_len: u8 = 0,

        salted_password_bytes: [salted_password_byte_len]u8 = .{0} ** salted_password_byte_len,
        salted_password_created: bool = false,

        status: SASLStatus = .init,

        pub const SASLStatus = enum {
            init,
            @"continue",
        };

        fn hmac(password: []const u8, data: []const u8) ?[32]u8 {
            var buf = std.mem.zeroes([bun.BoringSSL.c.EVP_MAX_MD_SIZE]u8);

            // TODO: I don't think this is failable.
            const result = bun.hmac.generate(password, data, .sha256, &buf) orelse return null;

            assert(result.len == 32);
            return buf[0..32].*;
        }

        pub fn computeSaltedPassword(this: *SASL, salt_bytes: []const u8, iteration_count: u32, connection: *PostgresSQLConnection) !void {
            this.salted_password_created = true;
            if (Crypto.EVP.pbkdf2(&this.salted_password_bytes, connection.password, salt_bytes, iteration_count, .sha256) == null) {
                return error.PBKDFD2;
            }
        }

        pub fn saltedPassword(this: *const SASL) []const u8 {
            assert(this.salted_password_created);
            return this.salted_password_bytes[0..salted_password_byte_len];
        }

        pub fn serverSignature(this: *const SASL) []const u8 {
            assert(this.server_signature_len > 0);
            return this.server_signature_base64_bytes[0..this.server_signature_len];
        }

        pub fn computeServerSignature(this: *SASL, auth_string: []const u8) !void {
            assert(this.server_signature_len == 0);

            const server_key = hmac(this.saltedPassword(), "Server Key") orelse return error.InvalidServerKey;
            const server_signature_bytes = hmac(&server_key, auth_string) orelse return error.InvalidServerSignature;
            this.server_signature_len = @intCast(bun.base64.encode(&this.server_signature_base64_bytes, &server_signature_bytes));
        }

        pub fn clientKey(this: *const SASL) [32]u8 {
            return hmac(this.saltedPassword(), "Client Key").?;
        }

        pub fn clientKeySignature(_: *const SASL, client_key: []const u8, auth_string: []const u8) [32]u8 {
            var sha_digest = std.mem.zeroes(bun.sha.SHA256.Digest);
            bun.sha.SHA256.hash(client_key, &sha_digest, JSC.VirtualMachine.get().rareData().boringEngine());
            return hmac(&sha_digest, auth_string).?;
        }

        pub fn nonce(this: *SASL) []const u8 {
            if (this.nonce_len == 0) {
                var bytes: [nonce_byte_len]u8 = .{0} ** nonce_byte_len;
                bun.csprng(&bytes);
                this.nonce_len = @intCast(bun.base64.encode(&this.nonce_base64_bytes, &bytes));
            }
            return this.nonce_base64_bytes[0..this.nonce_len];
        }

        pub fn deinit(this: *SASL) void {
            this.nonce_len = 0;
            this.salted_password_created = false;
            this.server_signature_len = 0;
            this.status = .init;
        }
    };

    pub const Status = enum {
        disconnected,
        connecting,
        // Prevent sending the startup message multiple times.
        // Particularly relevant for TLS connections.
        sent_startup_message,
        connected,
        failed,
    };

    pub const js = JSC.Codegen.JSPostgresSQLConnection;
    pub const toJS = js.toJS;
    pub const fromJS = js.fromJS;
    pub const fromJSDirect = js.fromJSDirect;

    fn getTimeoutInterval(this: *const PostgresSQLConnection) u32 {
        return switch (this.status) {
            .connected => this.idle_timeout_interval_ms,
            .failed => 0,
            else => this.connection_timeout_ms,
        };
    }
    pub fn disableConnectionTimeout(this: *PostgresSQLConnection) void {
        if (this.timer.state == .ACTIVE) {
            this.globalObject.bunVM().timer.remove(&this.timer);
        }
        this.timer.state = .CANCELLED;
    }
    pub fn resetConnectionTimeout(this: *PostgresSQLConnection) void {
        // if we are processing data, don't reset the timeout, wait for the data to be processed
        if (this.flags.is_processing_data) return;
        const interval = this.getTimeoutInterval();
        if (this.timer.state == .ACTIVE) {
            this.globalObject.bunVM().timer.remove(&this.timer);
        }
        if (interval == 0) {
            return;
        }

        this.timer.next = bun.timespec.msFromNow(@intCast(interval));
        this.globalObject.bunVM().timer.insert(&this.timer);
    }

    pub fn getQueries(_: *PostgresSQLConnection, thisValue: JSC.JSValue, globalObject: *JSC.JSGlobalObject) bun.JSError!JSC.JSValue {
        if (js.queriesGetCached(thisValue)) |value| {
            return value;
        }

        const array = try JSC.JSValue.createEmptyArray(globalObject, 0);
        js.queriesSetCached(thisValue, globalObject, array);

        return array;
    }

    pub fn getOnConnect(_: *PostgresSQLConnection, thisValue: JSC.JSValue, _: *JSC.JSGlobalObject) JSC.JSValue {
        if (js.onconnectGetCached(thisValue)) |value| {
            return value;
        }

        return .js_undefined;
    }

    pub fn setOnConnect(_: *PostgresSQLConnection, thisValue: JSC.JSValue, globalObject: *JSC.JSGlobalObject, value: JSC.JSValue) void {
        js.onconnectSetCached(thisValue, globalObject, value);
    }

    pub fn getOnClose(_: *PostgresSQLConnection, thisValue: JSC.JSValue, _: *JSC.JSGlobalObject) JSC.JSValue {
        if (js.oncloseGetCached(thisValue)) |value| {
            return value;
        }

        return .js_undefined;
    }

    pub fn setOnClose(_: *PostgresSQLConnection, thisValue: JSC.JSValue, globalObject: *JSC.JSGlobalObject, value: JSC.JSValue) void {
        js.oncloseSetCached(thisValue, globalObject, value);
    }

    pub fn setupTLS(this: *PostgresSQLConnection) void {
        debug("setupTLS", .{});
        const new_socket = this.socket.SocketTCP.socket.connected.upgrade(this.tls_ctx.?, this.tls_config.server_name) orelse {
            this.fail("Failed to upgrade to TLS", error.TLSUpgradeFailed);
            return;
        };
        this.socket = .{
            .SocketTLS = .{
                .socket = .{
                    .connected = new_socket,
                },
            },
        };

        this.start();
    }
    fn setupMaxLifetimeTimerIfNecessary(this: *PostgresSQLConnection) void {
        if (this.max_lifetime_interval_ms == 0) return;
        if (this.max_lifetime_timer.state == .ACTIVE) return;

        this.max_lifetime_timer.next = bun.timespec.msFromNow(@intCast(this.max_lifetime_interval_ms));
        this.globalObject.bunVM().timer.insert(&this.max_lifetime_timer);
    }

    pub fn onConnectionTimeout(this: *PostgresSQLConnection) bun.api.Timer.EventLoopTimer.Arm {
        debug("onConnectionTimeout", .{});

        this.timer.state = .FIRED;
        if (this.flags.is_processing_data) {
            return .disarm;
        }

        if (this.getTimeoutInterval() == 0) {
            this.resetConnectionTimeout();
            return .disarm;
        }

        switch (this.status) {
            .connected => {
                this.failFmt(.POSTGRES_IDLE_TIMEOUT, "Idle timeout reached after {}", .{bun.fmt.fmtDurationOneDecimal(@as(u64, this.idle_timeout_interval_ms) *| std.time.ns_per_ms)});
            },
            else => {
                this.failFmt(.POSTGRES_CONNECTION_TIMEOUT, "Connection timeout after {}", .{bun.fmt.fmtDurationOneDecimal(@as(u64, this.connection_timeout_ms) *| std.time.ns_per_ms)});
            },
            .sent_startup_message => {
                this.failFmt(.POSTGRES_CONNECTION_TIMEOUT, "Connection timed out after {} (sent startup message, but never received response)", .{bun.fmt.fmtDurationOneDecimal(@as(u64, this.connection_timeout_ms) *| std.time.ns_per_ms)});
            },
        }
        return .disarm;
    }

    pub fn onMaxLifetimeTimeout(this: *PostgresSQLConnection) bun.api.Timer.EventLoopTimer.Arm {
        debug("onMaxLifetimeTimeout", .{});
        this.max_lifetime_timer.state = .FIRED;
        if (this.status == .failed) return .disarm;
        this.failFmt(.POSTGRES_LIFETIME_TIMEOUT, "Max lifetime timeout reached after {}", .{bun.fmt.fmtDurationOneDecimal(@as(u64, this.max_lifetime_interval_ms) *| std.time.ns_per_ms)});
        return .disarm;
    }

    fn start(this: *PostgresSQLConnection) void {
        this.setupMaxLifetimeTimerIfNecessary();
        this.resetConnectionTimeout();
        this.sendStartupMessage();

        const event_loop = this.globalObject.bunVM().eventLoop();
        event_loop.enter();
        defer event_loop.exit();
        this.flushData();
    }

    pub fn hasPendingActivity(this: *PostgresSQLConnection) bool {
        return this.pending_activity_count.load(.acquire) > 0;
    }

    fn updateHasPendingActivity(this: *PostgresSQLConnection) void {
        const a: u32 = if (this.requests.readableLength() > 0) 1 else 0;
        const b: u32 = if (this.status != .disconnected) 1 else 0;
        this.pending_activity_count.store(a + b, .release);
    }

    pub fn setStatus(this: *PostgresSQLConnection, status: Status) void {
        if (this.status == status) return;
        defer this.updateHasPendingActivity();

        this.status = status;
        this.resetConnectionTimeout();

        switch (status) {
            .connected => {
                const on_connect = this.consumeOnConnectCallback(this.globalObject) orelse return;
                const js_value = this.js_value;
                js_value.ensureStillAlive();
                this.globalObject.queueMicrotask(on_connect, &[_]JSValue{ JSValue.jsNull(), js_value });
                this.poll_ref.unref(this.globalObject.bunVM());
            },
            else => {},
        }
    }

    pub fn finalize(this: *PostgresSQLConnection) void {
        debug("PostgresSQLConnection finalize", .{});
        this.stopTimers();
        this.js_value = .zero;
        this.deref();
    }

    pub fn flushDataAndResetTimeout(this: *PostgresSQLConnection) void {
        this.resetConnectionTimeout();
        this.flushData();
    }

    pub fn flushData(this: *PostgresSQLConnection) void {
        const chunk = this.write_buffer.remaining();
        if (chunk.len == 0) return;
        const wrote = this.socket.write(chunk, false);
        if (wrote > 0) {
            SocketMonitor.write(chunk[0..@intCast(wrote)]);
            this.write_buffer.consume(@intCast(wrote));
        }
    }

    pub fn failWithJSValue(this: *PostgresSQLConnection, value: JSValue) void {
        defer this.updateHasPendingActivity();
        this.stopTimers();
        if (this.status == .failed) return;

        this.status = .failed;

        this.ref();
        defer this.deref();
        // we defer the refAndClose so the on_close will be called first before we reject the pending requests
        defer this.refAndClose(value);
        const on_close = this.consumeOnCloseCallback(this.globalObject) orelse return;

        const loop = this.globalObject.bunVM().eventLoop();
        loop.enter();
        defer loop.exit();
        _ = on_close.call(
            this.globalObject,
            this.js_value,
            &[_]JSValue{
                value,
                this.getQueriesArray(),
            },
        ) catch |e| this.globalObject.reportActiveExceptionAsUnhandled(e);
    }

    pub fn failFmt(this: *PostgresSQLConnection, comptime error_code: JSC.Error, comptime fmt: [:0]const u8, args: anytype) void {
        this.failWithJSValue(error_code.fmt(this.globalObject, fmt, args));
    }

    pub fn fail(this: *PostgresSQLConnection, message: []const u8, err: AnyPostgresError) void {
        debug("failed: {s}: {s}", .{ message, @errorName(err) });

        const globalObject = this.globalObject;

        this.failWithJSValue(postgresErrorToJS(globalObject, message, err));
    }

    pub fn onClose(this: *PostgresSQLConnection) void {
        var vm = this.globalObject.bunVM();
        const loop = vm.eventLoop();
        loop.enter();
        defer loop.exit();
        this.poll_ref.unref(this.globalObject.bunVM());

        this.fail("Connection closed", error.ConnectionClosed);
    }

    fn sendStartupMessage(this: *PostgresSQLConnection) void {
        if (this.status != .connecting) return;
        debug("sendStartupMessage", .{});
        this.status = .sent_startup_message;
        var msg = protocol.StartupMessage{
            .user = Data{ .temporary = this.user },
            .database = Data{ .temporary = this.database },
            .options = Data{ .temporary = this.options },
        };
        msg.writeInternal(Writer, this.writer()) catch |err| {
            this.fail("Failed to write startup message", err);
        };
    }

    fn startTLS(this: *PostgresSQLConnection, socket: uws.AnySocket) void {
        debug("startTLS", .{});
        const offset = switch (this.tls_status) {
            .message_sent => |count| count,
            else => 0,
        };
        const ssl_request = [_]u8{
            0x00, 0x00, 0x00, 0x08, // Length
            0x04, 0xD2, 0x16, 0x2F, // SSL request code
        };

        const written = socket.write(ssl_request[offset..], false);
        if (written > 0) {
            this.tls_status = .{
                .message_sent = offset + @as(u8, @intCast(written)),
            };
        } else {
            this.tls_status = .{
                .message_sent = offset,
            };
        }
    }

    pub fn onOpen(this: *PostgresSQLConnection, socket: uws.AnySocket) void {
        this.socket = socket;

        this.poll_ref.ref(this.globalObject.bunVM());
        this.updateHasPendingActivity();

        if (this.tls_status == .message_sent or this.tls_status == .pending) {
            this.startTLS(socket);
            return;
        }

        this.start();
    }

    pub fn onHandshake(this: *PostgresSQLConnection, success: i32, ssl_error: uws.us_bun_verify_error_t) void {
        debug("onHandshake: {d} {d}", .{ success, ssl_error.error_no });
        const handshake_success = if (success == 1) true else false;
        if (handshake_success) {
            if (this.tls_config.reject_unauthorized != 0) {
                // only reject the connection if reject_unauthorized == true
                switch (this.ssl_mode) {
                    // https://github.com/porsager/postgres/blob/6ec85a432b17661ccacbdf7f765c651e88969d36/src/connection.js#L272-L279

                    .verify_ca, .verify_full => {
                        if (ssl_error.error_no != 0) {
                            this.failWithJSValue(ssl_error.toJS(this.globalObject));
                            return;
                        }

                        const ssl_ptr: *BoringSSL.c.SSL = @ptrCast(this.socket.getNativeHandle());
                        if (BoringSSL.c.SSL_get_servername(ssl_ptr, 0)) |servername| {
                            const hostname = servername[0..bun.len(servername)];
                            if (!BoringSSL.checkServerIdentity(ssl_ptr, hostname)) {
                                this.failWithJSValue(ssl_error.toJS(this.globalObject));
                            }
                        }
                    },
                    else => {
                        return;
                    },
                }
            }
        } else {
            // if we are here is because server rejected us, and the error_no is the cause of this
            // no matter if reject_unauthorized is false because we are disconnected by the server
            this.failWithJSValue(ssl_error.toJS(this.globalObject));
        }
    }

    pub fn onTimeout(this: *PostgresSQLConnection) void {
        _ = this;
        debug("onTimeout", .{});
    }

    pub fn onDrain(this: *PostgresSQLConnection) void {

        // Don't send any other messages while we're waiting for TLS.
        if (this.tls_status == .message_sent) {
            if (this.tls_status.message_sent < 8) {
                this.startTLS(this.socket);
            }

            return;
        }

        const event_loop = this.globalObject.bunVM().eventLoop();
        event_loop.enter();
        defer event_loop.exit();
        this.flushData();
    }

    pub fn onData(this: *PostgresSQLConnection, data: []const u8) void {
        this.ref();
        this.flags.is_processing_data = true;
        const vm = this.globalObject.bunVM();

        this.disableConnectionTimeout();
        defer {
            if (this.status == .connected and !this.hasQueryRunning() and this.write_buffer.remaining().len == 0) {
                // Don't keep the process alive when there's nothing to do.
                this.poll_ref.unref(vm);
            } else if (this.status == .connected) {
                // Keep the process alive if there's something to do.
                this.poll_ref.ref(vm);
            }
            this.flags.is_processing_data = false;

            // reset the connection timeout after we're done processing the data
            this.resetConnectionTimeout();
            this.deref();
        }

        const event_loop = vm.eventLoop();
        event_loop.enter();
        defer event_loop.exit();
        SocketMonitor.read(data);
        // reset the head to the last message so remaining reflects the right amount of bytes
        this.read_buffer.head = this.last_message_start;

        if (this.read_buffer.remaining().len == 0) {
            var consumed: usize = 0;
            var offset: usize = 0;
            const reader = protocol.StackReader.init(data, &consumed, &offset);
            PostgresRequest.onData(this, protocol.StackReader, reader) catch |err| {
                if (err == error.ShortRead) {
                    if (comptime bun.Environment.allow_assert) {
                        debug("read_buffer: empty and received short read: last_message_start: {d}, head: {d}, len: {d}", .{
                            offset,
                            consumed,
                            data.len,
                        });
                    }

                    this.read_buffer.head = 0;
                    this.last_message_start = 0;
                    this.read_buffer.byte_list.len = 0;
                    this.read_buffer.write(bun.default_allocator, data[offset..]) catch @panic("failed to write to read buffer");
                } else {
                    bun.handleErrorReturnTrace(err, @errorReturnTrace());

                    this.fail("Failed to read data", err);
                }
            };
            // no need to reset anything, its already empty
            return;
        }
        // read buffer is not empty, so we need to write the data to the buffer and then read it
        this.read_buffer.write(bun.default_allocator, data) catch @panic("failed to write to read buffer");
        PostgresRequest.onData(this, Reader, this.bufferedReader()) catch |err| {
            if (err != error.ShortRead) {
                bun.handleErrorReturnTrace(err, @errorReturnTrace());
                this.fail("Failed to read data", err);
                return;
            }

            if (comptime bun.Environment.allow_assert) {
                debug("read_buffer: not empty and received short read: last_message_start: {d}, head: {d}, len: {d}", .{
                    this.last_message_start,
                    this.read_buffer.head,
                    this.read_buffer.byte_list.len,
                });
            }
            return;
        };

        debug("clean read_buffer", .{});
        // success, we read everything! let's reset the last message start and the head
        this.last_message_start = 0;
        this.read_buffer.head = 0;
    }

    pub fn constructor(globalObject: *JSC.JSGlobalObject, callframe: *JSC.CallFrame) bun.JSError!*PostgresSQLConnection {
        _ = callframe;
        return globalObject.throw("PostgresSQLConnection cannot be constructed directly", .{});
    }

    comptime {
        const jscall = JSC.toJSHostFn(call);
        @export(&jscall, .{ .name = "PostgresSQLConnection__createInstance" });
    }

    pub fn call(globalObject: *JSC.JSGlobalObject, callframe: *JSC.CallFrame) bun.JSError!JSC.JSValue {
        var vm = globalObject.bunVM();
        const arguments = callframe.arguments_old(15).slice();
        const hostname_str = try arguments[0].toBunString(globalObject);
        defer hostname_str.deref();
        const port = arguments[1].coerce(i32, globalObject);

        const username_str = try arguments[2].toBunString(globalObject);
        defer username_str.deref();
        const password_str = try arguments[3].toBunString(globalObject);
        defer password_str.deref();
        const database_str = try arguments[4].toBunString(globalObject);
        defer database_str.deref();
        const ssl_mode: SSLMode = switch (arguments[5].toInt32()) {
            0 => .disable,
            1 => .prefer,
            2 => .require,
            3 => .verify_ca,
            4 => .verify_full,
            else => .disable,
        };

        const tls_object = arguments[6];

        var tls_config: JSC.API.ServerConfig.SSLConfig = .{};
        var tls_ctx: ?*uws.SocketContext = null;
        if (ssl_mode != .disable) {
            tls_config = if (tls_object.isBoolean() and tls_object.toBoolean())
                .{}
            else if (tls_object.isObject())
                (JSC.API.ServerConfig.SSLConfig.fromJS(vm, globalObject, tls_object) catch return .zero) orelse .{}
            else {
                return globalObject.throwInvalidArguments("tls must be a boolean or an object", .{});
            };

            if (globalObject.hasException()) {
                tls_config.deinit();
                return .zero;
            }

            // we always request the cert so we can verify it and also we manually abort the connection if the hostname doesn't match
            const original_reject_unauthorized = tls_config.reject_unauthorized;
            tls_config.reject_unauthorized = 0;
            tls_config.request_cert = 1;
            // We create it right here so we can throw errors early.
            const context_options = tls_config.asUSockets();
            var err: uws.create_bun_socket_error_t = .none;
            tls_ctx = uws.SocketContext.createSSLContext(vm.uwsLoop(), @sizeOf(*PostgresSQLConnection), context_options, &err) orelse {
                if (err != .none) {
                    return globalObject.throw("failed to create TLS context", .{});
                } else {
                    return globalObject.throwValue(err.toJS(globalObject));
                }
            };
            // restore the original reject_unauthorized
            tls_config.reject_unauthorized = original_reject_unauthorized;
            if (err != .none) {
                tls_config.deinit();
                if (tls_ctx) |ctx| {
                    ctx.deinit(true);
                }
                return globalObject.throwValue(err.toJS(globalObject));
            }

            uws.NewSocketHandler(true).configure(tls_ctx.?, true, *PostgresSQLConnection, SocketHandler(true));
        }

        var username: []const u8 = "";
        var password: []const u8 = "";
        var database: []const u8 = "";
        var options: []const u8 = "";
        var path: []const u8 = "";

        const options_str = try arguments[7].toBunString(globalObject);
        defer options_str.deref();

        const path_str = try arguments[8].toBunString(globalObject);
        defer path_str.deref();

        const options_buf: []u8 = brk: {
            var b = bun.StringBuilder{};
            b.cap += username_str.utf8ByteLength() + 1 + password_str.utf8ByteLength() + 1 + database_str.utf8ByteLength() + 1 + options_str.utf8ByteLength() + 1 + path_str.utf8ByteLength() + 1;

            b.allocate(bun.default_allocator) catch {};
            var u = username_str.toUTF8WithoutRef(bun.default_allocator);
            defer u.deinit();
            username = b.append(u.slice());

            var p = password_str.toUTF8WithoutRef(bun.default_allocator);
            defer p.deinit();
            password = b.append(p.slice());

            var d = database_str.toUTF8WithoutRef(bun.default_allocator);
            defer d.deinit();
            database = b.append(d.slice());

            var o = options_str.toUTF8WithoutRef(bun.default_allocator);
            defer o.deinit();
            options = b.append(o.slice());

            var _path = path_str.toUTF8WithoutRef(bun.default_allocator);
            defer _path.deinit();
            path = b.append(_path.slice());

            break :brk b.allocatedSlice();
        };

        const on_connect = arguments[9];
        const on_close = arguments[10];
        const idle_timeout = arguments[11].toInt32();
        const connection_timeout = arguments[12].toInt32();
        const max_lifetime = arguments[13].toInt32();
        const use_unnamed_prepared_statements = arguments[14].asBoolean();

        const ptr: *PostgresSQLConnection = try bun.default_allocator.create(PostgresSQLConnection);

        ptr.* = PostgresSQLConnection{
            .globalObject = globalObject,

            .database = database,
            .user = username,
            .password = password,
            .path = path,
            .options = options,
            .options_buf = options_buf,
            .socket = .{ .SocketTCP = .{ .socket = .{ .detached = {} } } },
            .requests = PostgresRequest.Queue.init(bun.default_allocator),
            .statements = PreparedStatementsMap{},
            .tls_config = tls_config,
            .tls_ctx = tls_ctx,
            .ssl_mode = ssl_mode,
            .tls_status = if (ssl_mode != .disable) .pending else .none,
            .idle_timeout_interval_ms = @intCast(idle_timeout),
            .connection_timeout_ms = @intCast(connection_timeout),
            .max_lifetime_interval_ms = @intCast(max_lifetime),
            .flags = .{
                .use_unnamed_prepared_statements = use_unnamed_prepared_statements,
            },
        };

        ptr.updateHasPendingActivity();
        ptr.poll_ref.ref(vm);
        const js_value = ptr.toJS(globalObject);
        js_value.ensureStillAlive();
        ptr.js_value = js_value;

        js.onconnectSetCached(js_value, globalObject, on_connect);
        js.oncloseSetCached(js_value, globalObject, on_close);
        bun.analytics.Features.postgres_connections += 1;

        {
            const hostname = hostname_str.toUTF8(bun.default_allocator);
            defer hostname.deinit();

            const ctx = vm.rareData().postgresql_context.tcp orelse brk: {
                const ctx_ = uws.SocketContext.createNoSSLContext(vm.uwsLoop(), @sizeOf(*PostgresSQLConnection)).?;
                uws.NewSocketHandler(false).configure(ctx_, true, *PostgresSQLConnection, SocketHandler(false));
                vm.rareData().postgresql_context.tcp = ctx_;
                break :brk ctx_;
            };

            if (path.len > 0) {
                ptr.socket = .{
                    .SocketTCP = uws.SocketTCP.connectUnixAnon(path, ctx, ptr, false) catch |err| {
                        tls_config.deinit();
                        if (tls_ctx) |tls| {
                            tls.deinit(true);
                        }
                        ptr.deinit();
                        return globalObject.throwError(err, "failed to connect to postgresql");
                    },
                };
            } else {
                ptr.socket = .{
                    .SocketTCP = uws.SocketTCP.connectAnon(hostname.slice(), port, ctx, ptr, false) catch |err| {
                        tls_config.deinit();
                        if (tls_ctx) |tls| {
                            tls.deinit(true);
                        }
                        ptr.deinit();
                        return globalObject.throwError(err, "failed to connect to postgresql");
                    },
                };
            }
            ptr.resetConnectionTimeout();
        }

        return js_value;
    }

    fn SocketHandler(comptime ssl: bool) type {
        return struct {
            const SocketType = uws.NewSocketHandler(ssl);
            fn _socket(s: SocketType) Socket {
                if (comptime ssl) {
                    return Socket{ .SocketTLS = s };
                }

                return Socket{ .SocketTCP = s };
            }
            pub fn onOpen(this: *PostgresSQLConnection, socket: SocketType) void {
                this.onOpen(_socket(socket));
            }

            fn onHandshake_(this: *PostgresSQLConnection, _: anytype, success: i32, ssl_error: uws.us_bun_verify_error_t) void {
                this.onHandshake(success, ssl_error);
            }

            pub const onHandshake = if (ssl) onHandshake_ else null;

            pub fn onClose(this: *PostgresSQLConnection, socket: SocketType, _: i32, _: ?*anyopaque) void {
                _ = socket;
                this.onClose();
            }

            pub fn onEnd(this: *PostgresSQLConnection, socket: SocketType) void {
                _ = socket;
                this.onClose();
            }

            pub fn onConnectError(this: *PostgresSQLConnection, socket: SocketType, _: i32) void {
                _ = socket;
                this.onClose();
            }

            pub fn onTimeout(this: *PostgresSQLConnection, socket: SocketType) void {
                _ = socket;
                this.onTimeout();
            }

            pub fn onData(this: *PostgresSQLConnection, socket: SocketType, data: []const u8) void {
                _ = socket;
                this.onData(data);
            }

            pub fn onWritable(this: *PostgresSQLConnection, socket: SocketType) void {
                _ = socket;
                this.onDrain();
            }
        };
    }

    pub fn ref(this: *@This()) void {
        bun.assert(this.ref_count > 0);
        this.ref_count += 1;
    }

    pub fn doRef(this: *@This(), _: *JSC.JSGlobalObject, _: *JSC.CallFrame) bun.JSError!JSValue {
        this.poll_ref.ref(this.globalObject.bunVM());
        this.updateHasPendingActivity();
        return .js_undefined;
    }

    pub fn doUnref(this: *@This(), _: *JSC.JSGlobalObject, _: *JSC.CallFrame) bun.JSError!JSValue {
        this.poll_ref.unref(this.globalObject.bunVM());
        this.updateHasPendingActivity();
        return .js_undefined;
    }
    pub fn doFlush(this: *PostgresSQLConnection, _: *JSC.JSGlobalObject, _: *JSC.CallFrame) bun.JSError!JSC.JSValue {
        this.flushData();
        return .js_undefined;
    }

    pub fn deref(this: *@This()) void {
        const ref_count = this.ref_count;
        this.ref_count -= 1;

        if (ref_count == 1) {
            this.disconnect();
            this.deinit();
        }
    }

    pub fn doClose(this: *@This(), globalObject: *JSC.JSGlobalObject, _: *JSC.CallFrame) bun.JSError!JSValue {
        _ = globalObject;
        this.disconnect();
        this.write_buffer.deinit(bun.default_allocator);

        return .js_undefined;
    }

    pub fn stopTimers(this: *PostgresSQLConnection) void {
        if (this.timer.state == .ACTIVE) {
            this.globalObject.bunVM().timer.remove(&this.timer);
        }
        if (this.max_lifetime_timer.state == .ACTIVE) {
            this.globalObject.bunVM().timer.remove(&this.max_lifetime_timer);
        }
    }

    pub fn deinit(this: *@This()) void {
        this.stopTimers();
        var iter = this.statements.valueIterator();
        while (iter.next()) |stmt_ptr| {
            var stmt = stmt_ptr.*;
            stmt.deref();
        }
        this.statements.deinit(bun.default_allocator);
        this.write_buffer.deinit(bun.default_allocator);
        this.read_buffer.deinit(bun.default_allocator);
        this.backend_parameters.deinit();

        bun.freeSensitive(bun.default_allocator, this.options_buf);

        this.tls_config.deinit();
        bun.default_allocator.destroy(this);
    }

    fn refAndClose(this: *@This(), js_reason: ?JSC.JSValue) void {
        // refAndClose is always called when we wanna to disconnect or when we are closed

        if (!this.socket.isClosed()) {
            // event loop need to be alive to close the socket
            this.poll_ref.ref(this.globalObject.bunVM());
            // will unref on socket close
            this.socket.close();
        }

        // cleanup requests
        while (this.current()) |request| {
            switch (request.status) {
                // pending we will fail the request and the stmt will be marked as error ConnectionClosed too
                .pending => {
                    const stmt = request.statement orelse continue;
                    stmt.error_response = .{ .postgres_error = AnyPostgresError.ConnectionClosed };
                    stmt.status = .failed;
                    if (js_reason) |reason| {
                        request.onJSError(reason, this.globalObject);
                    } else {
                        request.onError(.{ .postgres_error = AnyPostgresError.ConnectionClosed }, this.globalObject);
                    }
                },
                // in the middle of running
                .binding,
                .running,
                .partial_response,
                => {
                    if (js_reason) |reason| {
                        request.onJSError(reason, this.globalObject);
                    } else {
                        request.onError(.{ .postgres_error = AnyPostgresError.ConnectionClosed }, this.globalObject);
                    }
                },
                // just ignore success and fail cases
                .success, .fail => {},
            }
            request.deref();
            this.requests.discard(1);
        }
    }

    pub fn disconnect(this: *@This()) void {
        this.stopTimers();

        if (this.status == .connected) {
            this.status = .disconnected;
            this.refAndClose(null);
        }
    }

    fn current(this: *PostgresSQLConnection) ?*PostgresSQLQuery {
        if (this.requests.readableLength() == 0) {
            return null;
        }

        return this.requests.peekItem(0);
    }

    fn hasQueryRunning(this: *PostgresSQLConnection) bool {
        return !this.flags.is_ready_for_query or this.current() != null;
    }

    pub const Writer = struct {
        connection: *PostgresSQLConnection,

        pub fn write(this: Writer, data: []const u8) AnyPostgresError!void {
            var buffer = &this.connection.write_buffer;
            try buffer.write(bun.default_allocator, data);
        }

        pub fn pwrite(this: Writer, data: []const u8, index: usize) AnyPostgresError!void {
            @memcpy(this.connection.write_buffer.byte_list.slice()[index..][0..data.len], data);
        }

        pub fn offset(this: Writer) usize {
            return this.connection.write_buffer.len();
        }
    };

    pub fn writer(this: *PostgresSQLConnection) protocol.NewWriter(Writer) {
        return .{
            .wrapped = .{
                .connection = this,
            },
        };
    }

    pub const Reader = struct {
        connection: *PostgresSQLConnection,

        pub fn markMessageStart(this: Reader) void {
            this.connection.last_message_start = this.connection.read_buffer.head;
        }

        pub const ensureLength = ensureCapacity;

        pub fn peek(this: Reader) []const u8 {
            return this.connection.read_buffer.remaining();
        }
        pub fn skip(this: Reader, count: usize) void {
            this.connection.read_buffer.head = @min(this.connection.read_buffer.head + @as(u32, @truncate(count)), this.connection.read_buffer.byte_list.len);
        }
        pub fn ensureCapacity(this: Reader, count: usize) bool {
            return @as(usize, this.connection.read_buffer.head) + count <= @as(usize, this.connection.read_buffer.byte_list.len);
        }
        pub fn read(this: Reader, count: usize) AnyPostgresError!Data {
            var remaining = this.connection.read_buffer.remaining();
            if (@as(usize, remaining.len) < count) {
                return error.ShortRead;
            }

            this.skip(count);
            return Data{
                .temporary = remaining[0..count],
            };
        }
        pub fn readZ(this: Reader) AnyPostgresError!Data {
            const remain = this.connection.read_buffer.remaining();

            if (bun.strings.indexOfChar(remain, 0)) |zero| {
                this.skip(zero + 1);
                return Data{
                    .temporary = remain[0..zero],
                };
            }

            return error.ShortRead;
        }
    };

    pub fn bufferedReader(this: *PostgresSQLConnection) protocol.NewReader(Reader) {
        return .{
            .wrapped = .{ .connection = this },
        };
    }

    fn advance(this: *PostgresSQLConnection) !void {
        while (this.requests.readableLength() > 0) {
            var req: *PostgresSQLQuery = this.requests.peekItem(0);
            switch (req.status) {
                .pending => {
                    if (req.flags.simple) {
                        debug("executeQuery", .{});
                        var query_str = req.query.toUTF8(bun.default_allocator);
                        defer query_str.deinit();
                        PostgresRequest.executeQuery(query_str.slice(), PostgresSQLConnection.Writer, this.writer()) catch |err| {
                            req.onWriteFail(err, this.globalObject, this.getQueriesArray());
                            req.deref();
                            this.requests.discard(1);

                            continue;
                        };
                        this.flags.is_ready_for_query = false;
                        req.status = .running;
                        return;
                    } else {
                        const stmt = req.statement orelse return error.ExpectedStatement;

                        switch (stmt.status) {
                            .failed => {
                                bun.assert(stmt.error_response != null);
                                req.onError(stmt.error_response.?, this.globalObject);
                                req.deref();
                                this.requests.discard(1);

                                continue;
                            },
                            .prepared => {
                                const thisValue = req.thisValue.get();
                                bun.assert(thisValue != .zero);
                                const binding_value = PostgresSQLQuery.js.bindingGetCached(thisValue) orelse .zero;
                                const columns_value = PostgresSQLQuery.js.columnsGetCached(thisValue) orelse .zero;
                                req.flags.binary = stmt.fields.len > 0;

                                PostgresRequest.bindAndExecute(this.globalObject, stmt, binding_value, columns_value, PostgresSQLConnection.Writer, this.writer()) catch |err| {
                                    req.onWriteFail(err, this.globalObject, this.getQueriesArray());
                                    req.deref();
                                    this.requests.discard(1);

                                    continue;
                                };
                                this.flags.is_ready_for_query = false;
                                req.status = .binding;
                                return;
                            },
                            .pending => {
                                // statement is pending, lets write/parse it
                                var query_str = req.query.toUTF8(bun.default_allocator);
                                defer query_str.deinit();
                                const has_params = stmt.signature.fields.len > 0;
                                // If it does not have params, we can write and execute immediately in one go
                                if (!has_params) {
                                    const thisValue = req.thisValue.get();
                                    bun.assert(thisValue != .zero);
                                    // prepareAndQueryWithSignature will write + bind + execute, it will change to running after binding is complete
                                    const binding_value = PostgresSQLQuery.js.bindingGetCached(thisValue) orelse .zero;
                                    PostgresRequest.prepareAndQueryWithSignature(this.globalObject, query_str.slice(), binding_value, PostgresSQLConnection.Writer, this.writer(), &stmt.signature) catch |err| {
                                        stmt.status = .failed;
                                        stmt.error_response = .{ .postgres_error = err };
                                        req.onWriteFail(err, this.globalObject, this.getQueriesArray());
                                        req.deref();
                                        this.requests.discard(1);

                                        continue;
                                    };
                                    this.flags.is_ready_for_query = false;
                                    req.status = .binding;
                                    stmt.status = .parsing;

                                    return;
                                }
                                const connection_writer = this.writer();
                                // write query and wait for it to be prepared
                                PostgresRequest.writeQuery(query_str.slice(), stmt.signature.prepared_statement_name, stmt.signature.fields, PostgresSQLConnection.Writer, connection_writer) catch |err| {
                                    stmt.error_response = .{ .postgres_error = err };
                                    stmt.status = .failed;

                                    req.onWriteFail(err, this.globalObject, this.getQueriesArray());
                                    req.deref();
                                    this.requests.discard(1);

                                    continue;
                                };
                                connection_writer.write(&protocol.Sync) catch |err| {
                                    stmt.error_response = .{ .postgres_error = err };
                                    stmt.status = .failed;

                                    req.onWriteFail(err, this.globalObject, this.getQueriesArray());
                                    req.deref();
                                    this.requests.discard(1);

                                    continue;
                                };
                                this.flags.is_ready_for_query = false;
                                stmt.status = .parsing;
                                return;
                            },
                            .parsing => {
                                // we are still parsing, lets wait for it to be prepared or failed
                                return;
                            },
                        }
                    }
                },

                .running, .binding, .partial_response => {
                    // if we are binding it will switch to running immediately
                    // if we are running, we need to wait for it to be success or fail
                    return;
                },
                .success, .fail => {
                    req.deref();
                    this.requests.discard(1);
                    continue;
                },
            }
        }
    }

    pub fn getQueriesArray(this: *const PostgresSQLConnection) JSValue {
        return js.queriesGetCached(this.js_value) orelse .zero;
    }

    pub const DataCell = @import("./DataCell.zig").DataCell;

    pub fn on(this: *PostgresSQLConnection, comptime MessageType: @Type(.enum_literal), comptime Context: type, reader: protocol.NewReader(Context)) AnyPostgresError!void {
        debug("on({s})", .{@tagName(MessageType)});

        switch (comptime MessageType) {
            .DataRow => {
                const request = this.current() orelse return error.ExpectedRequest;
                var statement = request.statement orelse return error.ExpectedStatement;
                var structure: JSValue = .js_undefined;
                var cached_structure: ?PostgresCachedStructure = null;
                // explicit use switch without else so if new modes are added, we don't forget to check for duplicate fields
                switch (request.flags.result_mode) {
                    .objects => {
                        cached_structure = statement.structure(this.js_value, this.globalObject);
                        structure = cached_structure.?.jsValue() orelse .js_undefined;
                    },
                    .raw, .values => {
                        // no need to check for duplicate fields or structure
                    },
                }

                var putter = DataCell.Putter{
                    .list = &.{},
                    .fields = statement.fields,
                    .binary = request.flags.binary,
                    .bigint = request.flags.bigint,
                    .globalObject = this.globalObject,
                };

                var stack_buf: [70]DataCell = undefined;
                var cells: []DataCell = stack_buf[0..@min(statement.fields.len, JSC.JSObject.maxInlineCapacity())];
                var free_cells = false;
                defer {
                    for (cells[0..putter.count]) |*cell| {
                        cell.deinit();
                    }
                    if (free_cells) bun.default_allocator.free(cells);
                }

                if (statement.fields.len >= JSC.JSObject.maxInlineCapacity()) {
                    cells = try bun.default_allocator.alloc(DataCell, statement.fields.len);
                    free_cells = true;
                }
                // make sure all cells are reset if reader short breaks the fields will just be null with is better than undefined behavior
                @memset(cells, DataCell{ .tag = .null, .value = .{ .null = 0 } });
                putter.list = cells;

                if (request.flags.result_mode == .raw) {
                    try protocol.DataRow.decode(
                        &putter,
                        Context,
                        reader,
                        DataCell.Putter.putRaw,
                    );
                } else {
                    try protocol.DataRow.decode(
                        &putter,
                        Context,
                        reader,
                        DataCell.Putter.put,
                    );
                }
                const thisValue = request.thisValue.get();
                bun.assert(thisValue != .zero);
                const pending_value = PostgresSQLQuery.js.pendingValueGetCached(thisValue) orelse .zero;
                pending_value.ensureStillAlive();
                const result = putter.toJS(this.globalObject, pending_value, structure, statement.fields_flags, request.flags.result_mode, cached_structure);

                if (pending_value == .zero) {
                    PostgresSQLQuery.js.pendingValueSetCached(thisValue, this.globalObject, result);
                }
            },
            .CopyData => {
                var copy_data: protocol.CopyData = undefined;
                try copy_data.decodeInternal(Context, reader);
                copy_data.data.deinit();
            },
            .ParameterStatus => {
                var parameter_status: protocol.ParameterStatus = undefined;
                try parameter_status.decodeInternal(Context, reader);
                defer {
                    parameter_status.deinit();
                }
                try this.backend_parameters.insert(parameter_status.name.slice(), parameter_status.value.slice());
            },
            .ReadyForQuery => {
                var ready_for_query: protocol.ReadyForQuery = undefined;
                try ready_for_query.decodeInternal(Context, reader);

                this.setStatus(.connected);
                this.flags.is_ready_for_query = true;
                this.socket.setTimeout(300);
                defer this.updateRef();

                if (this.current()) |request| {
                    if (request.status == .partial_response) {
                        // if is a partial response, just signal that the query is now complete
                        request.onResult("", this.globalObject, this.js_value, true);
                    }
                }
                try this.advance();

                this.flushData();
            },
            .CommandComplete => {
                var request = this.current() orelse return error.ExpectedRequest;

                var cmd: protocol.CommandComplete = undefined;
                try cmd.decodeInternal(Context, reader);
                defer {
                    cmd.deinit();
                }
                debug("-> {s}", .{cmd.command_tag.slice()});
                defer this.updateRef();

                if (request.flags.simple) {
                    // simple queries can have multiple commands
                    request.onResult(cmd.command_tag.slice(), this.globalObject, this.js_value, false);
                } else {
                    request.onResult(cmd.command_tag.slice(), this.globalObject, this.js_value, true);
                }
            },
            .BindComplete => {
                try reader.eatMessage(protocol.BindComplete);
                var request = this.current() orelse return error.ExpectedRequest;
                if (request.status == .binding) {
                    request.status = .running;
                }
            },
            .ParseComplete => {
                try reader.eatMessage(protocol.ParseComplete);
                const request = this.current() orelse return error.ExpectedRequest;
                if (request.statement) |statement| {
                    // if we have params wait for parameter description
                    if (statement.status == .parsing and statement.signature.fields.len == 0) {
                        statement.status = .prepared;
                    }
                }
            },
            .ParameterDescription => {
                var description: protocol.ParameterDescription = undefined;
                try description.decodeInternal(Context, reader);
                const request = this.current() orelse return error.ExpectedRequest;
                var statement = request.statement orelse return error.ExpectedStatement;
                statement.parameters = description.parameters;
                if (statement.status == .parsing) {
                    statement.status = .prepared;
                }
            },
            .RowDescription => {
                var description: protocol.RowDescription = undefined;
                try description.decodeInternal(Context, reader);
                errdefer description.deinit();
                const request = this.current() orelse return error.ExpectedRequest;
                var statement = request.statement orelse return error.ExpectedStatement;
                statement.fields = description.fields;
            },
            .Authentication => {
                var auth: protocol.Authentication = undefined;
                try auth.decodeInternal(Context, reader);
                defer auth.deinit();

                switch (auth) {
                    .SASL => {
                        if (this.authentication_state != .SASL) {
                            this.authentication_state = .{ .SASL = .{} };
                        }

                        var mechanism_buf: [128]u8 = undefined;
                        const mechanism = std.fmt.bufPrintZ(&mechanism_buf, "n,,n=*,r={s}", .{this.authentication_state.SASL.nonce()}) catch unreachable;
                        var response = protocol.SASLInitialResponse{
                            .mechanism = .{
                                .temporary = "SCRAM-SHA-256",
                            },
                            .data = .{
                                .temporary = mechanism,
                            },
                        };

                        try response.writeInternal(PostgresSQLConnection.Writer, this.writer());
                        debug("SASL", .{});
                        this.flushData();
                    },
                    .SASLContinue => |*cont| {
                        if (this.authentication_state != .SASL) {
                            debug("Unexpected SASLContinue for authentiation state: {s}", .{@tagName(std.meta.activeTag(this.authentication_state))});
                            return error.UnexpectedMessage;
                        }
                        var sasl = &this.authentication_state.SASL;

                        if (sasl.status != .init) {
                            debug("Unexpected SASLContinue for SASL state: {s}", .{@tagName(sasl.status)});
                            return error.UnexpectedMessage;
                        }
                        debug("SASLContinue", .{});

                        const iteration_count = try cont.iterationCount();

                        const server_salt_decoded_base64 = bun.base64.decodeAlloc(bun.z_allocator, cont.s) catch |err| {
                            return switch (err) {
                                error.DecodingFailed => error.SASL_SIGNATURE_INVALID_BASE64,
                                else => |e| e,
                            };
                        };
                        defer bun.z_allocator.free(server_salt_decoded_base64);
                        try sasl.computeSaltedPassword(server_salt_decoded_base64, iteration_count, this);

                        const auth_string = try std.fmt.allocPrint(
                            bun.z_allocator,
                            "n=*,r={s},r={s},s={s},i={s},c=biws,r={s}",
                            .{
                                sasl.nonce(),
                                cont.r,
                                cont.s,
                                cont.i,
                                cont.r,
                            },
                        );
                        defer bun.z_allocator.free(auth_string);
                        try sasl.computeServerSignature(auth_string);

                        const client_key = sasl.clientKey();
                        const client_key_signature = sasl.clientKeySignature(&client_key, auth_string);
                        var client_key_xor_buffer: [32]u8 = undefined;
                        for (&client_key_xor_buffer, client_key, client_key_signature) |*out, a, b| {
                            out.* = a ^ b;
                        }

                        var client_key_xor_base64_buf = std.mem.zeroes([bun.base64.encodeLenFromSize(32)]u8);
                        const xor_base64_len = bun.base64.encode(&client_key_xor_base64_buf, &client_key_xor_buffer);

                        const payload = try std.fmt.allocPrint(
                            bun.z_allocator,
                            "c=biws,r={s},p={s}",
                            .{ cont.r, client_key_xor_base64_buf[0..xor_base64_len] },
                        );
                        defer bun.z_allocator.free(payload);

                        var response = protocol.SASLResponse{
                            .data = .{
                                .temporary = payload,
                            },
                        };

                        try response.writeInternal(PostgresSQLConnection.Writer, this.writer());
                        sasl.status = .@"continue";
                        this.flushData();
                    },
                    .SASLFinal => |final| {
                        if (this.authentication_state != .SASL) {
                            debug("SASLFinal - Unexpected SASLContinue for authentiation state: {s}", .{@tagName(std.meta.activeTag(this.authentication_state))});
                            return error.UnexpectedMessage;
                        }
                        var sasl = &this.authentication_state.SASL;

                        if (sasl.status != .@"continue") {
                            debug("SASLFinal - Unexpected SASLContinue for SASL state: {s}", .{@tagName(sasl.status)});
                            return error.UnexpectedMessage;
                        }

                        if (sasl.server_signature_len == 0) {
                            debug("SASLFinal - Server signature is empty", .{});
                            return error.UnexpectedMessage;
                        }

                        const server_signature = sasl.serverSignature();

                        // This will usually start with "v="
                        const comparison_signature = final.data.slice();

                        if (comparison_signature.len < 2 or !bun.strings.eqlLong(server_signature, comparison_signature[2..], true)) {
                            debug("SASLFinal - SASL Server signature mismatch\nExpected: {s}\nActual: {s}", .{ server_signature, comparison_signature[2..] });
                            this.fail("The server did not return the correct signature", error.SASL_SIGNATURE_MISMATCH);
                        } else {
                            debug("SASLFinal - SASL Server signature match", .{});
                            this.authentication_state.zero();
                        }
                    },
                    .Ok => {
                        debug("Authentication OK", .{});
                        this.authentication_state.zero();
                        this.authentication_state = .{ .ok = {} };
                    },

                    .Unknown => {
                        this.fail("Unknown authentication method", error.UNKNOWN_AUTHENTICATION_METHOD);
                    },

                    .ClearTextPassword => {
                        debug("ClearTextPassword", .{});
                        var response = protocol.PasswordMessage{
                            .password = .{
                                .temporary = this.password,
                            },
                        };

                        try response.writeInternal(PostgresSQLConnection.Writer, this.writer());
                        this.flushData();
                    },

                    .MD5Password => |md5| {
                        debug("MD5Password", .{});
                        // Format is: md5 + md5(md5(password + username) + salt)
                        var first_hash_buf: bun.sha.MD5.Digest = undefined;
                        var first_hash_str: [32]u8 = undefined;
                        var final_hash_buf: bun.sha.MD5.Digest = undefined;
                        var final_hash_str: [32]u8 = undefined;
                        var final_password_buf: [36]u8 = undefined;

                        // First hash: md5(password + username)
                        var first_hasher = bun.sha.MD5.init();
                        first_hasher.update(this.password);
                        first_hasher.update(this.user);
                        first_hasher.final(&first_hash_buf);
                        const first_hash_str_output = std.fmt.bufPrint(&first_hash_str, "{x}", .{std.fmt.fmtSliceHexLower(&first_hash_buf)}) catch unreachable;

                        // Second hash: md5(first_hash + salt)
                        var final_hasher = bun.sha.MD5.init();
                        final_hasher.update(first_hash_str_output);
                        final_hasher.update(&md5.salt);
                        final_hasher.final(&final_hash_buf);
                        const final_hash_str_output = std.fmt.bufPrint(&final_hash_str, "{x}", .{std.fmt.fmtSliceHexLower(&final_hash_buf)}) catch unreachable;

                        // Format final password as "md5" + final_hash
                        const final_password = std.fmt.bufPrintZ(&final_password_buf, "md5{s}", .{final_hash_str_output}) catch unreachable;

                        var response = protocol.PasswordMessage{
                            .password = .{
                                .temporary = final_password,
                            },
                        };

                        this.authentication_state = .{ .md5 = {} };
                        try response.writeInternal(PostgresSQLConnection.Writer, this.writer());
                        this.flushData();
                    },

                    else => {
                        debug("TODO auth: {s}", .{@tagName(std.meta.activeTag(auth))});
                        this.fail("TODO: support authentication method: {s}", error.UNSUPPORTED_AUTHENTICATION_METHOD);
                    },
                }
            },
            .NoData => {
                try reader.eatMessage(protocol.NoData);
                var request = this.current() orelse return error.ExpectedRequest;
                if (request.status == .binding) {
                    request.status = .running;
                }
            },
            .BackendKeyData => {
                try this.backend_key_data.decodeInternal(Context, reader);
            },
            .ErrorResponse => {
                var err: protocol.ErrorResponse = undefined;
                try err.decodeInternal(Context, reader);

                if (this.status == .connecting or this.status == .sent_startup_message) {
                    defer {
                        err.deinit();
                    }

                    this.failWithJSValue(err.toJS(this.globalObject));

                    // it shouldn't enqueue any requests while connecting
                    bun.assert(this.requests.count == 0);
                    return;
                }

                var request = this.current() orelse {
                    debug("ErrorResponse: {}", .{err});
                    return error.ExpectedRequest;
                };
                var is_error_owned = true;
                defer {
                    if (is_error_owned) {
                        err.deinit();
                    }
                }
                if (request.statement) |stmt| {
                    if (stmt.status == PostgresSQLStatement.Status.parsing) {
                        stmt.status = PostgresSQLStatement.Status.failed;
                        stmt.error_response = .{ .protocol = err };
                        is_error_owned = false;
                        if (this.statements.remove(bun.hash(stmt.signature.name))) {
                            stmt.deref();
                        }
                    }
                }
                this.updateRef();

                request.onError(.{ .protocol = err }, this.globalObject);
            },
            .PortalSuspended => {
                // try reader.eatMessage(&protocol.PortalSuspended);
                // var request = this.current() orelse return error.ExpectedRequest;
                // _ = request;
                debug("TODO PortalSuspended", .{});
            },
            .CloseComplete => {
                try reader.eatMessage(protocol.CloseComplete);
                var request = this.current() orelse return error.ExpectedRequest;
                defer this.updateRef();
                if (request.flags.simple) {
                    request.onResult("CLOSECOMPLETE", this.globalObject, this.js_value, false);
                } else {
                    request.onResult("CLOSECOMPLETE", this.globalObject, this.js_value, true);
                }
            },
            .CopyInResponse => {
                debug("TODO CopyInResponse", .{});
            },
            .NoticeResponse => {
                debug("UNSUPPORTED NoticeResponse", .{});
                var resp: protocol.NoticeResponse = undefined;

                try resp.decodeInternal(Context, reader);
                resp.deinit();
            },
            .EmptyQueryResponse => {
                try reader.eatMessage(protocol.EmptyQueryResponse);
                var request = this.current() orelse return error.ExpectedRequest;
                defer this.updateRef();
                if (request.flags.simple) {
                    request.onResult("", this.globalObject, this.js_value, false);
                } else {
                    request.onResult("", this.globalObject, this.js_value, true);
                }
            },
            .CopyOutResponse => {
                debug("TODO CopyOutResponse", .{});
            },
            .CopyDone => {
                debug("TODO CopyDone", .{});
            },
            .CopyBothResponse => {
                debug("TODO CopyBothResponse", .{});
            },
            else => @compileError("Unknown message type: " ++ @tagName(MessageType)),
        }
    }

    pub fn updateRef(this: *PostgresSQLConnection) void {
        this.updateHasPendingActivity();
        if (this.pending_activity_count.raw > 0) {
            this.poll_ref.ref(this.globalObject.bunVM());
        } else {
            this.poll_ref.unref(this.globalObject.bunVM());
        }
    }

    pub fn getConnected(this: *PostgresSQLConnection, _: *JSC.JSGlobalObject) JSValue {
        return JSValue.jsBoolean(this.status == Status.connected);
    }

    pub fn consumeOnConnectCallback(this: *const PostgresSQLConnection, globalObject: *JSC.JSGlobalObject) ?JSC.JSValue {
        debug("consumeOnConnectCallback", .{});
        const on_connect = js.onconnectGetCached(this.js_value) orelse return null;
        debug("consumeOnConnectCallback exists", .{});

        js.onconnectSetCached(this.js_value, globalObject, .zero);
        return on_connect;
    }

    pub fn consumeOnCloseCallback(this: *const PostgresSQLConnection, globalObject: *JSC.JSGlobalObject) ?JSC.JSValue {
        debug("consumeOnCloseCallback", .{});
        const on_close = js.oncloseGetCached(this.js_value) orelse return null;
        debug("consumeOnCloseCallback exists", .{});
        js.oncloseSetCached(this.js_value, globalObject, .zero);
        return on_close;
    }
};

pub const PostgresCachedStructure = struct {
    structure: JSC.Strong.Optional = .empty,
    // only populated if more than JSC.JSC__JSObject__maxInlineCapacity fields otherwise the structure will contain all fields inlined
    fields: ?[]JSC.JSObject.ExternColumnIdentifier = null,

    pub fn has(this: *@This()) bool {
        return this.structure.has() or this.fields != null;
    }

    pub fn jsValue(this: *const @This()) ?JSC.JSValue {
        return this.structure.get();
    }

    pub fn set(this: *@This(), globalObject: *JSC.JSGlobalObject, value: ?JSC.JSValue, fields: ?[]JSC.JSObject.ExternColumnIdentifier) void {
        if (value) |v| {
            this.structure.set(globalObject, v);
        }
        this.fields = fields;
    }

    pub fn deinit(this: *@This()) void {
        this.structure.deinit();
        if (this.fields) |fields| {
            this.fields = null;
            for (fields) |*name| {
                name.deinit();
            }
            bun.default_allocator.free(fields);
        }
    }
};
pub const PostgresSQLStatement = struct {
    cached_structure: PostgresCachedStructure = .{},
    ref_count: u32 = 1,
    fields: []protocol.FieldDescription = &[_]protocol.FieldDescription{},
    parameters: []const int4 = &[_]int4{},
    signature: Signature,
    status: Status = Status.pending,
    error_response: ?Error = null,
    needs_duplicate_check: bool = true,
    fields_flags: PostgresSQLConnection.DataCell.Flags = .{},

    pub const Error = union(enum) {
        protocol: protocol.ErrorResponse,
        postgres_error: AnyPostgresError,

        pub fn deinit(this: *@This()) void {
            switch (this.*) {
                .protocol => |*err| err.deinit(),
                .postgres_error => {},
            }
        }

        pub fn toJS(this: *const @This(), globalObject: *JSC.JSGlobalObject) JSValue {
            return switch (this.*) {
                .protocol => |err| err.toJS(globalObject),
                .postgres_error => |err| postgresErrorToJS(globalObject, null, err),
            };
        }
    };
    pub const Status = enum {
        pending,
        parsing,
        prepared,
        failed,

        pub fn isRunning(this: @This()) bool {
            return this == .parsing;
        }
    };
    pub fn ref(this: *@This()) void {
        bun.assert(this.ref_count > 0);
        this.ref_count += 1;
    }

    pub fn deref(this: *@This()) void {
        const ref_count = this.ref_count;
        this.ref_count -= 1;

        if (ref_count == 1) {
            this.deinit();
        }
    }

    pub fn checkForDuplicateFields(this: *PostgresSQLStatement) void {
        if (!this.needs_duplicate_check) return;
        this.needs_duplicate_check = false;

        var seen_numbers = std.ArrayList(u32).init(bun.default_allocator);
        defer seen_numbers.deinit();
        var seen_fields = bun.StringHashMap(void).init(bun.default_allocator);
        seen_fields.ensureUnusedCapacity(@intCast(this.fields.len)) catch bun.outOfMemory();
        defer seen_fields.deinit();

        // iterate backwards
        var remaining = this.fields.len;
        var flags: PostgresSQLConnection.DataCell.Flags = .{};
        while (remaining > 0) {
            remaining -= 1;
            const field: *protocol.FieldDescription = &this.fields[remaining];
            switch (field.name_or_index) {
                .name => |*name| {
                    const seen = seen_fields.getOrPut(name.slice()) catch unreachable;
                    if (seen.found_existing) {
                        field.name_or_index = .duplicate;
                        flags.has_duplicate_columns = true;
                    }

                    flags.has_named_columns = true;
                },
                .index => |index| {
                    if (std.mem.indexOfScalar(u32, seen_numbers.items, index) != null) {
                        field.name_or_index = .duplicate;
                        flags.has_duplicate_columns = true;
                    } else {
                        seen_numbers.append(index) catch bun.outOfMemory();
                    }

                    flags.has_indexed_columns = true;
                },
                .duplicate => {
                    flags.has_duplicate_columns = true;
                },
            }
        }

        this.fields_flags = flags;
    }

    pub fn deinit(this: *PostgresSQLStatement) void {
        debug("PostgresSQLStatement deinit", .{});

        bun.assert(this.ref_count == 0);

        for (this.fields) |*field| {
            field.deinit();
        }
        bun.default_allocator.free(this.fields);
        bun.default_allocator.free(this.parameters);
        this.cached_structure.deinit();
        if (this.error_response) |err| {
            this.error_response = null;
            var _error = err;
            _error.deinit();
        }
        this.signature.deinit();
        bun.default_allocator.destroy(this);
    }

    pub fn structure(this: *PostgresSQLStatement, owner: JSValue, globalObject: *JSC.JSGlobalObject) PostgresCachedStructure {
        if (this.cached_structure.has()) {
            return this.cached_structure;
        }
        this.checkForDuplicateFields();

        // lets avoid most allocations
        var stack_ids: [70]JSC.JSObject.ExternColumnIdentifier = undefined;
        // lets de duplicate the fields early
        var nonDuplicatedCount = this.fields.len;
        for (this.fields) |*field| {
            if (field.name_or_index == .duplicate) {
                nonDuplicatedCount -= 1;
            }
        }
        const ids = if (nonDuplicatedCount <= JSC.JSObject.maxInlineCapacity()) stack_ids[0..nonDuplicatedCount] else bun.default_allocator.alloc(JSC.JSObject.ExternColumnIdentifier, nonDuplicatedCount) catch bun.outOfMemory();

        var i: usize = 0;
        for (this.fields) |*field| {
            if (field.name_or_index == .duplicate) continue;

            var id: *JSC.JSObject.ExternColumnIdentifier = &ids[i];
            switch (field.name_or_index) {
                .name => |name| {
                    id.value.name = String.createAtomIfPossible(name.slice());
                },
                .index => |index| {
                    id.value.index = index;
                },
                .duplicate => unreachable,
            }
            id.tag = switch (field.name_or_index) {
                .name => 2,
                .index => 1,
                .duplicate => 0,
            };
            i += 1;
        }

        if (nonDuplicatedCount > JSC.JSObject.maxInlineCapacity()) {
            this.cached_structure.set(globalObject, null, ids);
        } else {
            this.cached_structure.set(globalObject, JSC.JSObject.createStructure(
                globalObject,
                owner,
                @truncate(ids.len),
                ids.ptr,
            ), null);
        }

        return this.cached_structure;
    }
};

const QueryBindingIterator = union(enum) {
    array: JSC.JSArrayIterator,
    objects: ObjectIterator,

    pub fn init(array: JSValue, columns: JSValue, globalObject: *JSC.JSGlobalObject) bun.JSError!QueryBindingIterator {
        if (columns.isEmptyOrUndefinedOrNull()) {
            return .{ .array = try JSC.JSArrayIterator.init(array, globalObject) };
        }

        return .{
            .objects = .{
                .array = array,
                .columns = columns,
                .globalObject = globalObject,
                .columns_count = try columns.getLength(globalObject),
                .array_length = try array.getLength(globalObject),
            },
        };
    }

    pub const ObjectIterator = struct {
        array: JSValue,
        columns: JSValue = .zero,
        globalObject: *JSC.JSGlobalObject,
        cell_i: usize = 0,
        row_i: usize = 0,
        current_row: JSC.JSValue = .zero,
        columns_count: usize = 0,
        array_length: usize = 0,
        any_failed: bool = false,

        pub fn next(this: *ObjectIterator) ?JSC.JSValue {
            if (this.row_i >= this.array_length) {
                return null;
            }

            const cell_i = this.cell_i;
            this.cell_i += 1;
            const row_i = this.row_i;

            const globalObject = this.globalObject;

            if (this.current_row == .zero) {
                this.current_row = JSC.JSObject.getIndex(this.array, globalObject, @intCast(row_i)) catch {
                    this.any_failed = true;
                    return null;
                };
                if (this.current_row.isEmptyOrUndefinedOrNull()) {
                    return globalObject.throw("Expected a row to be returned at index {d}", .{row_i}) catch null;
                }
            }

            defer {
                if (this.cell_i >= this.columns_count) {
                    this.cell_i = 0;
                    this.current_row = .zero;
                    this.row_i += 1;
                }
            }

            const property = JSC.JSObject.getIndex(this.columns, globalObject, @intCast(cell_i)) catch {
                this.any_failed = true;
                return null;
            };
            if (property.isUndefined()) {
                return globalObject.throw("Expected a column at index {d} in row {d}", .{ cell_i, row_i }) catch null;
            }

            const value = this.current_row.getOwnByValue(globalObject, property);
            if (value == .zero or (value != null and value.?.isUndefined())) {
                if (!globalObject.hasException())
                    return globalObject.throw("Expected a value at index {d} in row {d}", .{ cell_i, row_i }) catch null;
                this.any_failed = true;
                return null;
            }
            return value;
        }
    };

    pub fn next(this: *QueryBindingIterator) bun.JSError!?JSC.JSValue {
        return switch (this.*) {
            .array => |*iter| iter.next(),
            .objects => |*iter| iter.next(),
        };
    }

    pub fn anyFailed(this: *const QueryBindingIterator) bool {
        return switch (this.*) {
            .array => false,
            .objects => |*iter| iter.any_failed,
        };
    }

    pub fn to(this: *QueryBindingIterator, index: u32) void {
        switch (this.*) {
            .array => |*iter| iter.i = index,
            .objects => |*iter| {
                iter.cell_i = index % iter.columns_count;
                iter.row_i = index / iter.columns_count;
                iter.current_row = .zero;
            },
        }
    }

    pub fn reset(this: *QueryBindingIterator) void {
        switch (this.*) {
            .array => |*iter| {
                iter.i = 0;
            },
            .objects => |*iter| {
                iter.cell_i = 0;
                iter.row_i = 0;
                iter.current_row = .zero;
            },
        }
    }
};

const Signature = struct {
    fields: []const int4,
    name: []const u8,
    query: []const u8,
    prepared_statement_name: []const u8,

    pub fn empty() Signature {
        return Signature{
            .fields = &[_]int4{},
            .name = &[_]u8{},
            .query = &[_]u8{},
            .prepared_statement_name = &[_]u8{},
        };
    }

    const log = bun.Output.scoped(.PostgresSignature, false);
    pub fn deinit(this: *Signature) void {
        if (this.prepared_statement_name.len > 0) {
            bun.default_allocator.free(this.prepared_statement_name);
        }
        if (this.name.len > 0) {
            bun.default_allocator.free(this.name);
        }
        if (this.fields.len > 0) {
            bun.default_allocator.free(this.fields);
        }
        if (this.query.len > 0) {
            bun.default_allocator.free(this.query);
        }
    }

    pub fn hash(this: *const Signature) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(this.name);
        hasher.update(std.mem.sliceAsBytes(this.fields));
        return hasher.final();
    }

    pub fn generate(globalObject: *JSC.JSGlobalObject, query: []const u8, array_value: JSValue, columns: JSValue, prepared_statement_id: u64, unnamed: bool) !Signature {
        var fields = std.ArrayList(int4).init(bun.default_allocator);
        var name = try std.ArrayList(u8).initCapacity(bun.default_allocator, query.len);

        name.appendSliceAssumeCapacity(query);

        errdefer {
            fields.deinit();
            name.deinit();
        }

        var iter = try QueryBindingIterator.init(array_value, columns, globalObject);

        while (try iter.next()) |value| {
            if (value.isEmptyOrUndefinedOrNull()) {
                // Allow postgres to decide the type
                try fields.append(0);
                try name.appendSlice(".null");
                continue;
            }

            const tag = try types.Tag.fromJS(globalObject, value);

            switch (tag) {
                .int8 => try name.appendSlice(".int8"),
                .int4 => try name.appendSlice(".int4"),
                // .int4_array => try name.appendSlice(".int4_array"),
                .int2 => try name.appendSlice(".int2"),
                .float8 => try name.appendSlice(".float8"),
                .float4 => try name.appendSlice(".float4"),
                .numeric => try name.appendSlice(".numeric"),
                .json, .jsonb => try name.appendSlice(".json"),
                .bool => try name.appendSlice(".bool"),
                .timestamp => try name.appendSlice(".timestamp"),
                .timestamptz => try name.appendSlice(".timestamptz"),
                .bytea => try name.appendSlice(".bytea"),
                else => try name.appendSlice(".string"),
            }

            switch (tag) {
                .bool, .int4, .int8, .float8, .int2, .numeric, .float4, .bytea => {
                    // We decide the type
                    try fields.append(@intFromEnum(tag));
                },
                else => {
                    // Allow postgres to decide the type
                    try fields.append(0);
                },
            }
        }

        if (iter.anyFailed()) {
            return error.InvalidQueryBinding;
        }
        // max u64 length is 20, max prepared_statement_name length is 63
        const prepared_statement_name = if (unnamed) "" else try std.fmt.allocPrint(bun.default_allocator, "P{s}${d}", .{ name.items[0..@min(40, name.items.len)], prepared_statement_id });

        return Signature{
            .prepared_statement_name = prepared_statement_name,
            .name = name.items,
            .fields = fields.items,
            .query = try bun.default_allocator.dupe(u8, query),
        };
    }
};

pub fn createBinding(globalObject: *JSC.JSGlobalObject) JSValue {
    const binding = JSValue.createEmptyObjectWithNullPrototype(globalObject);
    binding.put(globalObject, ZigString.static("PostgresSQLConnection"), PostgresSQLConnection.js.getConstructor(globalObject));
    binding.put(globalObject, ZigString.static("init"), JSC.JSFunction.create(globalObject, "init", PostgresSQLContext.init, 0, .{}));
    binding.put(
        globalObject,
        ZigString.static("createQuery"),
        JSC.JSFunction.create(globalObject, "createQuery", PostgresSQLQuery.call, 6, .{}),
    );

    binding.put(
        globalObject,
        ZigString.static("createConnection"),
        JSC.JSFunction.create(globalObject, "createQuery", PostgresSQLConnection.call, 2, .{}),
    );

    return binding;
}

const ZigString = JSC.ZigString;

const assert = bun.assert;
