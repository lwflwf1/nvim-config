-- SystemVerilog value toggling (<leader>sw): cycles the word under the cursor
-- through the group it belongs to in `toggle_dict`.
local M = {}

local toggle_dict = {
    { "&", "|" },
    { "~", "!" },
    { "always_ff", "always_latch", "always_comb" },
    { "posedge", "negedge" },
    { "logic", "bit" },
    { "@", "wait" },
    { " <=", " =" },
    { "input", "output", "ref" },
    { "'b", "'h", "'d" },
    { "endfunction", "endtask", "endclass", "endinterface", "endmodule", "end", "endclocking" },
    { "function", "task" },
    { "WRITE", "READ" },
}

local function toggle_value()
    local word = vim.fn.expand("<cword>")
    for _, group in ipairs(toggle_dict) do
        for i, v in ipairs(group) do
            if word == v then
                local next = group[i % #group + 1]
                vim.cmd("normal! ciw" .. next)
                return
            end
        end
    end
end

function M.setup()
    vim.keymap.set("n", "<leader>sw", toggle_value,
        { noremap = true, silent = true, desc = "Toggle value" })
end

return M
