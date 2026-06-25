structure:

<img width="181" height="130" alt="image" src="https://github.com/user-attachments/assets/b18b734f-13f4-4721-9eac-1e6eded3aed1" />

usage:

    assembles assembly source into an object file
    if passing module script, must return source (valid assembly) as a buffer
    assembler.assemble(file: ModuleScript | buffer)

      
    searches folder for module script named "main"
    if found: calls .assemble(main)
    .assemble_folder(folder: Folder)

    !!this is redundant!!
    does .assemble(buf)
    .assemble_buffer(buf: buffer)

    was using this to export buffers to my local server to put them in HxD
    .export(b: buffer)

    takes an object file (as buffer), "serializes" it into a roblox module script, then returns the module script
    when requiring this modulescript, it reconstructs the object file and returns it as a buffer
    .serialize(obj: buffer)
