local api = vim.api
local fn = vim.fn
local config = require("java_helper").config

-- 1) Detecta paquete base desde *Application.java
local function find_base_package(root)
	if config.base_package or config.base_path then
		local pkg = config.base_package or ""
		local path = fn.fnamemodify(root .. "/" .. (config.base_path or "src/main/java"), ":p")
		return pkg, path
	end

	local src = root .. "/src/main/java"
	local apps = fn.globpath(src, "**/*Application.java", false, true)
	if #apps == 0 then
		apps = fn.globpath(src, "**/*Main.java", false, true)
	end
	if #apps == 0 then
		vim.notify("nvim-java-helper: no se encontró *Application.java ni *Main.java", vim.log.levels.ERROR)
		return nil, nil
	end

	local app = fn.resolve(apps[1])
	local src_abs = fn.resolve(src)

	if not vim.startswith(app, src_abs) then
		return nil, nil
	end

	local rel = app:sub(#src_abs + 2)
	local dir = fn.fnamemodify(rel, ":h")
	local pkg = dir:gsub("/", ".")
	local abs = fn.fnamemodify(src .. "/" .. dir, ":p")

	return pkg, abs
end

-- 2) Carga la plantilla
local function load_template(kind)
	local pattern = "java_helper/templates/" .. kind .. ".java.tpl"
	local files = api.nvim_get_runtime_file(pattern, false)
	if #files == 0 then
		error("nvim-java-helper: plantilla no encontrada -> " .. kind)
	end
	-- ✅ Corregido: \n en lugar de "

	return table.concat(fn.readfile(files[1]), "\n")
end

-- 3) Reemplaza placeholders
local function render(tpl, vars)
	return tpl:gsub("${PACKAGE}", vars.package):gsub("${NAME}", vars.name)
end

-- 4) Crea la clase
local function create_from_template(kind, sub_pkg, is_test)
	local cwd = fn.getcwd()
	local base_pkg, _ = find_base_package(cwd)
	if not base_pkg then
		return
	end

	-- Aseguramos limpieza
	sub_pkg = sub_pkg:gsub("^%s*(.-)%s*$", "%1")

	-- ✅ Usa el paquete base detectado
	local full_pkg = base_pkg == "" and sub_pkg or (base_pkg .. "." .. sub_pkg)

	-- ✅ Divide manualmente por punto (seguro)
	local parts = {}
	for part in full_pkg:gmatch("[^%.]+") do
		table.insert(parts, part)
	end

	-- Nombre de clase = última parte
	local name = parts[#parts]
	if not name or name == "" then
		vim.notify("nvim-java-helper: nombre de clase inválido", vim.log.levels.ERROR)
		return
	end

	-- Remueve nombre para obtener paquete
	parts[#parts] = nil
	local package = table.concat(parts, ".")
	local pkg_path = table.concat(parts, "/")

	-- Directorio destino
	local root_dir = is_test and cwd .. "/src/test/java" or cwd .. "/src/main/java"
	local target_dir = root_dir .. "/" .. pkg_path
	fn.mkdir(target_dir, "p")

	-- Nombre del archivo
	local file_name = name

	-- Para tests: User -> UserTest
	if is_test then
		if not name:match("Test$") then
			file_name = name .. "Test"
		end
	end

	local file_path = target_dir .. "/" .. file_name .. ".java"

	if fn.filereadable(file_path) == 1 then
		vim.notify("nvim-java-helper: el archivo ya existe → " .. file_path, vim.log.levels.WARN)
		vim.cmd.edit(file_path)
		return
	end

	local tpl = load_template(kind)
	-- Renderiza con el nombre real de la clase (User o UserTest)
	local class_name = is_test and file_name or name
	tpl = render(tpl, { package = package, name = class_name })

	-- ✅ Usa \n
	fn.writefile(vim.split(tpl, "\n"), file_path)
	api.nvim_command("edit " .. file_path)
end

-- 5) Comandos con input interactivo
local function create_input_command(kind, is_test)
	return function()
		vim.ui.input({
			prompt = "[" .. kind .. "] Clase (ej: user.User) > ",
		}, function(input)
			if input and input ~= "" then
				create_from_template(kind, input, is_test)
			else
				vim.notify("nvim-java-helper: operación cancelada o entrada vacía", vim.log.levels.INFO)
			end
		end)
	end
end

local commands = {
	{ kind = "Class", is_test = false, cmd = "NewJavaClass" },
	{ kind = "Interface", is_test = false, cmd = "NewJavaInterface" },
	{ kind = "Enum", is_test = false, cmd = "NewJavaEnum" },
	{ kind = "Annotation", is_test = false, cmd = "NewJavaAnnotation" },
	{ kind = "Record", is_test = false, cmd = "NewJavaRecord" },
	{ kind = "Test", is_test = true, cmd = "NewJavaTest" },
	{ kind = "SpringBootApplication", is_test = false, cmd = "NewSpringBootApplication" },
}

for _, c in ipairs(commands) do
	vim.api.nvim_create_user_command(c.cmd, create_input_command(c.kind, c.is_test), {
		nargs = 0,
		desc = "nvim-java-helper: crea un(a) " .. c.kind .. " con entrada interactiva",
	})
end
