local M = {}
local default_config = {
	base_package = nil,
	base_path = nil,
}

M.config = default_config

--- Setup: mezcla tu configuración con los valores por defecto
---@param opts table?
function M.setup(opts)
	if opts and type(opts) == "table" then
		M.config = vim.tbl_deep_extend("force", default_config, opts)
	end
	-- al hacer setup, cargamos los comandos (si no lo hicimos ya)
	require("java_helper.commands")
end

return M
