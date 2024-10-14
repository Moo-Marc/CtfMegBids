function BidsRenameSubjects(BidsFolder, RenameFile)
    % Rename BIDS subjects based on csv file with two columns: "OldName", "NewName".
    %
    % First row (column names) is ignored, the column order determines old vs
    % new names.  "sub-" is not required and ignored where present.

    isFull = true;

    % Load spreadsheet, only first 2 columns, skip header line.
    Names = readcell(RenameFile, 'NumHeaderLines', 1, 'Range', 'A:B');
    Names = replace(Names, 'sub-', '');
    % Remove '_' and '-'.
    Names = replace(Names, {'_', '-'}, '');
    % Rename.
    for iSub = 1:size(Names, 1)
        fprintf('Renaming %s to %s.\n', Names{iSub, 1}, Names{iSub, 2});
        BidsRenameSubject(BidsFolder, Names{iSub, 1}, Names{iSub, 2}, isFull);
    end
    fprintf('\nDone renaming!\n\n');
end
