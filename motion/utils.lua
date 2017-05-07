function dir()
    for k,v in pairs(file.list()) do
       print(k .. " Size: " .. v)
    end
end
