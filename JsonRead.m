function J = JsonRead(File)
    fid = fopen(File, 'r');
    if (fid < 0)
        warning(['Cannot open JSON file: ' File]);
    end
    % Read file
    inString = fread(fid, [1, Inf], '*char');
    % Close file
    fclose(fid);
    J = jsondecode(inString);
end