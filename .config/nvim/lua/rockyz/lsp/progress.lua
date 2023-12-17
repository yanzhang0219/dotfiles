-----------------------------------------------
-- The underlying principle behind LSP progress
-----------------------------------------------
--
-- Each LSP client object (:h vim.lsp.client) has a member called progress. It's a ring buffer
-- (vim.ringbuf) to store the progress message sent from the server.
--
-- Progress is a kind of notification send by the server. A notification's structure defined by LSP
-- is shown as below. LSP is based on JSON-RPC protocol (https://www.jsonrpc.org/specification) that
-- uses JSON as data format for communication between the server and client. Neovim will encode
-- (vim.json.encode) and decode (vim.json.decode) to do the conversion between Lua table and JSON.
-- So here I use Lua table to describe the structure of the progress notification.
-- (Ref:
-- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#progress)
-- {
--   method = '$/progress',
--   params =  {
--     token = ...,
--     value = {
--       ...    -- see below
--     },
-- }
-- For work down progress, the value can be of three different forms:
-- (Ref:
-- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#workDoneProgress)
-- 1. Work down progress begin
-- {
--   kind = 'begin',
--   title = ...,
--   cancellable = ...,    -- optional
--   message = ...,    -- optional
--   percentage = ...,    -- optional
-- }
-- 2. Work down progress report
-- {
--   kind = 'report',
--   cancellable = ...,     -- optional
--   message = ...,    -- optional
--   percentage = ...,    -- optional
-- }
-- 3. Work down progress end
-- {
--   kind = 'end',
--   message = ...,    -- optional
-- }
--
-- When each progress notification sent by the server is received, $/process handler will be invoked
-- to process the notification. See its source code in runtime/lua/vim/lsp/handler.lua. The pramas
-- part will be passed to the handler function as the result. The handler pushes the result (i.e.,
-- the pramas) into the ring buffer of the corresponding client (i.e., client.progress) and then
-- trigger LspProgress autocmd event. When LspProgress is triggered, its callback will be invoked
-- with a table argument. The argument has a data table with two fields:
-- 1. data.client_id
-- 2. data.result: the pramas part
-- For details, see the source code in runtime/lua/vim/lsp/handler.lua
--
-- So we can use the callback function of LspProgress to get the progress information we need.
-- 1. Directly from the args passed into the callback such as args.data.result.value.title for the
--    the title of the progress notification. Each time we can print one progress message.
-- 2. Call vim.lsp.status() in the callback. It gets the progress message in the ring buffer and
--    emptys the ring buffer, and it is called for each arrived notification, so in each call of
--    status() only a single one message will be printed.

---------------------------
-- More on vim.lsp.status()
---------------------------
--
-- In each call of status() function, it will iterate all the active clients. In each client, it
-- **CONSUMES** all the progress messages in the ring buffer. Its implementation is very inspiring.
-- The trick is this line of code `for progress in client.progress do`. This is a generic for
-- statement.
--
-- Short explanation about the generic for statement:
-- (In Lua, for statement has two forms, numerical and generic)
-- In this generic for statement `for ele in xxx do`, xxx is an iterator (An iterator is a function
-- and each time when the function is called, it returns a "next" element from a collection and nil
-- when no more elements in the collection). When the for loop is executed, at each iteration, the
-- iterator will be called and the returned value will be asigned to ele, and the loop will
-- terminate when the iterator returns nil.
-- Take `for k, v in pairs(t) do` as an example. When this for statement is executed, it first calls
-- pairs() to get an iterator, and then in each iteration this iterator will be called.
-- More about the iterator and generic for, see https://www.lua.org/pil/7.html
--
-- We know that client.progress is a ring buffer. A ring buffer actually is a table. The table not
-- only stores the items pushed in it (self._items) but also maintain necessary variables to keep
-- track of its own state (self._size, self._idx_read, self._idx_write, etc). In the metatable of
-- this table, we define __call to pop out the first item by self:pop(), so the table is callable. Back to that
-- tricky for loop `for progress in client.progress do`, in each iteration, client.progres as an
-- iterator will be called and it pops out the first item. The for loop terminates when the iterator
-- returns nil, i.e., no more items in the ring buffer of the client. So for each vim.lsp.status()
-- call, it will print all the items (i.e., the progress messages) in the ring buffers of all the
-- active clients, and all the ring buffers will be empty. This is what the **COMSUMES** means.
--
-- More about vim.ringbuf's definition and operations, see its source code
-- https://github.com/neovim/neovim/blob/master/runtime/lua/vim/shared.lua

--------------
-- More on LSP
--------------
--
-- There are three types of communication between the client (i.e., the development tool) and the
-- language server:
-- 1. The client sends a request, the server gets the request and return the corresponding response.
--    E.g., the textDocument/definition (Goto Definition) request.
-- 2. The server sends a request, the client gets the request and return the corresponding response.
--    E.g., the workspace/inlayHint/refresh (Inlay Hint Refresh) request.
-- 3. Both client and server can send a notification to each other, and must not send a response
--    back. E.g., the $/progress notification can be sent from the client or the server.
--
-- There is an diagram example illustrating how the client (development tool) and server
-- communicate, see https://microsoft.github.io/language-server-protocol/overviews/lsp/overview/
--
-- In Neovim, the client and server communicate through stdio. The process of establishing a
-- connection and communication bewteen the client and server is as follows:
-- * Call vim.lsp.start_client({config}). It will create a LSP client (:h vim.lsp.client). The
-- config parameter has a cmd field that is a command to launch a LSP server.
-- * In start_client, it calls vim.lsp.rpc.start(cmd). In rpc.start(), it first creates a RPC
-- client. NOTE: so far we have two kinds of clients, LSP client and RPC client. The LSP client
-- created in the first step above is upper level for exposing APIs such as
-- vim.lsp.buf_request_all() to uses. Actually it's just a wrapper of the RPC client. The LSP
-- operations such as sending request are performed through the underlying RPC client.
-- * Next, rpc.start() will call vim.system(cmd, {opts}) by passing a system command cmd and an
-- options {opts} containing three important fields, stdin, stdout and stderr. These three fields
-- will be explained below. vim.system() will run cmd to launch the LSP server and return a
-- vim.SystemObj object (:h vim.system). Under the hood, vim.system uses uv.spawn(cmd, stdio) to
-- initialize and start a process to run the server. stdio is used to communicate with the process
-- running the server.
--   1. stdin: set to true to create a pipe used to connect to stdin (stdin = uv.new_pipe()). A
--      request to LSP server is send through the stdin. When we send a request to the LSP server by
--      calling an APIs such as vim.lsp.buf_request_all(), it uses SystemObj's write() method (which
--      calls stdin:write(data)) to write the request data into the pipe.
--   2. stdout: a handler to handle the output from stdout. In vim.system, a pipe will be created
--      (uv.new_pipe) to connect to the stdout. The response sent by the server will be put to the
--      stdout. The stdout handler will get the response (it has two parts, header and content) and
--      pass the content part into the handle_body(content) function (check it out in
--      runtime/lua/vim/lsp/rpc.lua). handle_body() will call the corresponding handler of the
--      response (based on the request's method) with the result field in the response's content
--      part as the argument. For notification, it is handled in the same way as the response.
--   3. stderr: a handler to handle the output from stderr. In vim.system, a pipe will be created
--      and connect to the stderr.
--
-- Neovim also provides another option to support the communication between the client and server,
-- namely through TCP. For example, language server Godot only supports TCP. So we need to set the
-- cmd to vim.lsp.rpc.connect('127.0.0.1', os.getenv('GDScript_Port')) when we call
-- vim.lsp.start_client(). For details, see the source file (gdscript.lua) in nvim-lspconfig. The
-- method vim.lsp.rpc.connect() will return a function. vim.lsp.start_client() will call this
-- returned funtion to create a RPC client and connect to the server via tcp:connect(host, port).
-- When we send a request to the server, tcp:write() will be called. To handle the response, it's
-- almost the same with stdout. See the source code of vim.lsp.rpc.connect() function for details.

--
-- I use the args passed in the callback of LspProgress to get the progress message. If there are
-- multiple servers sending progress nofitications at the same time, display the message from
-- different servers in a separate window.
local icons = {
  spinner = { '⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷' },
  done = ''
}

-- Maintain the status of each window showing progress message. Each one is indexed by the client id
-- and has these fields:
--  - is_done: whether the progress is finished. If so, remove the window.
--  - spinner_idx: current index of the spinner
--  - winid: winid of the floating window
--  - bufnr: bufnr of the floating window
--  - win_row: row position of the floating window
local clients = {}
local wins_cnt = 0

vim.api.nvim_create_autocmd({ 'LspProgress' }, {
  group = vim.api.nvim_create_augroup('lsp_progress', { clear = true }),
  pattern = '*',
  callback = function(args)
    if not args.data then
      return
    end

    local id = args.data.client_id
    if clients[id] == nil then
      clients[id] = {
        is_done = false,
        spinner_idx = 0,
      }
    end
    -- Assemble the output progress message
    -- - General: ⣾ [client_name] title: message ( 5%)
    -- - Done:     [client_name] title: DONE!
    local output = ''
    local client_name = vim.lsp.get_client_by_id(id).name
    output = '[' .. client_name .. ']'
    local kind = args.data.result.value.kind
    local title = args.data.result.value.title
    if title then
      output = output .. ' ' .. title .. ':'
    end
    if kind == 'end' then
      clients[id].is_done = true
      output = icons.done .. ' ' .. output .. ' DONE!'
    else
      clients[id].is_done = false
      local msg = args.data.result.value.message
      local pct = args.data.result.value.percentage
      if msg then
        output = output .. ' ' .. msg
      end
      if pct then
        output = string.format('%s (%3d%%)', output, pct)
      end
      -- Spinner
      local idx = clients[id].spinner_idx
      idx = idx == #icons.spinner * 4 and 1 or idx + 1
      output = icons.spinner[math.ceil(idx / 4)] .. ' ' .. output
      clients[id].spinner_idx = idx
    end

    -- The row position of the floating window for the current client. If there are multiple
    -- windows, show it right on the top.
    local win_row = clients[id].win_row
    if win_row == nil then
      win_row = vim.o.lines - vim.o.cmdheight - 4 - wins_cnt * 3
      clients[id].win_row = win_row
    end

    local winid = clients[id].winid
    local bufnr = clients[id].bufnr
    -- If the window for showing the progress message of the current client doesn't exist, we create
    -- it; otherwise we just adjust its size.
    if
      winid == nil
      or not vim.api.nvim_win_is_valid(winid)
      or vim.api.nvim_win_get_tabpage(winid) ~= vim.api.nvim_get_current_tabpage()
    then
      bufnr = vim.api.nvim_create_buf(false, true)
      winid = vim.api.nvim_open_win(bufnr, false, {
        relative = 'editor',
        width = #output,
        height = 1,
        row = win_row,
        col = vim.o.columns - #output,
        style = 'minimal',
        noautocmd = true,
        border = vim.g.border_style,
      })
      clients[id].bufnr = bufnr
      clients[id].winid = winid
      wins_cnt = wins_cnt + 1
    else
      vim.api.nvim_win_set_config(winid, {
        relative = 'editor',
        width = #output,
        row = win_row,
        col = vim.o.columns - #output,
      })
    end
    -- Put the progress message in the buffer of the window
    vim.wo[winid].winhl = 'Normal:Normal'
    vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { output })
    -- If the progress finishes, we should remove the window along with deleting its buffer. But
    -- in order to see the final message, let it stay on the screen for a few seconds.
    if clients[id].is_done then
      vim.defer_fn(function()
        if vim.api.nvim_win_is_valid(winid) then
          vim.api.nvim_win_close(winid, true)
        end
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_delete(bufnr, { force = true })
        end
        wins_cnt = wins_cnt - 1
        clients[id].winid = nil
        clients[id].spinner_idx = 0
      end, 5000)
    end
  end,
})
