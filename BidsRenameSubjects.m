function BidsRenameSubjects(BidsFolder, RenameFile)
    % Rename BIDS subjects based on csv file with two columns: "OldName", "NewName".
    %
    % First row (column names) is ignored, the column order determines old vs
    % new names.  "sub-" is not required and ignored where present.

    % Load spreadsheet.
    Names = readcell(RenameFile, 'NumHeaderLines', 1);
    Names = replace(Names, 'sub-', '');
    % Remove '_' and '-'.
    Names = replace(Names, {'_', '-'}, '');
    % Rename.
    for iSub = 1:size(Names, 1)
        BidsRenameSubject(BidsFolder, Names{iSub, 1}, Names{iSub, 2});
    end

end
