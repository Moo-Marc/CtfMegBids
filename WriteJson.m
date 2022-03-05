function WriteJson(JsonFile, JsonStruct)
    Fid = fopen(JsonFile, 'w'); % don't write /r/n even on Windows.
    if Fid < 0
        % Try changing permissions
        system(sprintf('chmod u+w %s', JsonFile));
        Fid = fopen(JsonFile, 'w');
        if Fid < 0
            error('Unable to open file %s for writing.', JsonFile);
        end
    end
    JsonText = bst_jsonencode(JsonStruct, true); % indent -> force bst
    % '%s' required otherwise would need to escape more characters, '', %%, etc.
    fprintf(Fid, '%s', JsonText);
    fclose(Fid);
end
