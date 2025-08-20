local api = vim.api
local fn = vim.fn
local config = require("java_helper").config

-- 1) Detecta paquete base desde *Application.java o *Main.java
local function find_base_package(root)
	-- override manual (desde setup)
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
		vim.notify(
			"nvim-java-helper: no se encontró *Application.java ni *Main.java en src/main/java",
			vim.log.levels.ERROR
		)
		return nil, nil
	end

	local app = apps[1]
	local src_abs = fn.resolve(src)
	local app_abs = fn.resolve(app)

	-- Verifica que el archivo esté dentro de src/main/java
	if not vim.startswith(app_abs, src_abs) then
		return nil, nil
	end

	-- Extrae la ruta relativa después de src/main/java
	local rel = app_abs:sub(#src_abs + 2) -- +2 para saltar la barra
	local dir = fn.fnamemodify(rel, ":h") -- directorio del archivo
	local pkg = dir:gsub("/", ".") -- convierte a paquete Java
	local abs = fn.fnamemodify(src .. "/" .. dir, ":p")

	return pkg, abs
end

-- 2) Carga la plantilla desde java_helper/templates/*.java.tpl
local function load_template(kind)
	local pattern = "java_helper/templates/" .. kind .. ".java.tpl"
	local files = api.nvim_get_runtime_file(pattern, false)
	if #files == 0 then
		error("nvim-java-helper: plantilla no encontrada -> " .. kind)
	end
	return table.concat(fn.readfile(files[1]), "\n")
end

-- 3) Reemplaza solo ${PACKAGE} y ${NAME} (mayúsculas)
local function render(tpl, vars)
	return tpl:gsub("${PACKAGE}", vars.package):gsub("${NAME}", vars.name)
end

-- 4) Crea la clase Java
local function create_from_template(kind, sub_pkg, is_test)
	local cwd = fn.getcwd()
	local base_pkg, _ = find_base_package(cwd)
	if not base_pkg then
		return -- ya se notificó en find_base_package
	end

	-- Construye el paquete completo: com.example.demo.user.User
	local full_pkg = base_pkg == "" and sub_pkg or (base_pkg .. "." .. sub_pkg)
	local parts = fn.split(full_pkg, "%.") -- divide por punto literal
	local name = parts[#parts] -- nombre de clase: User
	parts[#parts] = nil -- remueve el nombre
	local package = table.concat(parts, ".") -- paquete: com.example.demo.user
	local pkg_path = table.concat(parts, "/") -- ruta: com/example/demo/user

	local root_dir = is_test and cwd .. "/src/test/java" or cwd .. "/src/main/java"
	local target_dir = root_dir .. "/" .. pkg_path
	fn.mkdir(target_dir, "p")

	local file_path = target_dir .. "/" .. name .. ".java"

	if fn.filereadable(file_path) == 1 then
		vim.notify("nvim-java-helper: el archivo ya existe → " .. file_path, vim.log.levels.WARN)
		vim.cmd.edit(file_path)
		return
	end

	local tpl = load_template(kind)
	tpl = render(tpl, { package = package, name = name })

	fn.writefile(vim.split(tpl, "\n"), file_path)
	api.nvim_command("edit " .. file_path)
end

-- 5) Registra comandos
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
	vim.api.nvim_create_user_command(c.cmd, function(opts)
		create_from_template(c.kind, opts.args, c.is_test)
	end, {
		nargs = 1,
		desc = "nvim-java-helper: crea un(a) " .. c.kind .. " en el paquete detectado",
	})
end
