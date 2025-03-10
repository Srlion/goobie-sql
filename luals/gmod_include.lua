function ResolveRequire(uri, name)
    return { uri .. "/sql/lua/" .. name }
end
