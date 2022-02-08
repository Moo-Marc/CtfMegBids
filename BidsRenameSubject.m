function BidsRenameSubject(BidsFolder, OldNamePart, NewNamePart)
    % Rename a subject ID everywhere in a CTF MEG BIDS dataset.
    %
    % Files, folders, inside BIDS scans.tsv and inside raw data files. Includes
    % elsewhere in potential "sub-datasets": sourcedata, derivatives, extras,
    % etc. 
    %   
    % Marc Lalancette 2022-02-07
    
    OldExpr = ['sub-([a-zA-Z0-9]*)', OldNamePart, '([a-zA-Z0-9]*)_ses'];
    NewExpr = ['sub-$1', NewNamePart, '$2_ses'];

    % Rename recordings first, including inside raw data files (infods, res4, xml, etc.).
    List = dir(fullfile(BidsFolder, '**', ['*sub-*', OldNamePart, '*_ses*.ds']));
    for f = 1:numel(List)
        Bids_ctf_rename_ds(fullfile(List(f).folder, List(f).name), ...
            regexprep(List(f).name, OldExpr, NewExpr));
    end

    % Rename other files.
    List = dir(fullfile(BidsFolder, '**', ['*sub-*', OldNamePart, '*_ses*']));
    List([List.isdir]) = [];
    for f = 1:numel(List)
        [IsOk, Message] = movefile(fullfile(List(f).folder, List(f).name), ...
            fullfile(List(f).folder, regexprep(List(f).name, OldExpr, NewExpr)));
        if ~IsOk
            error(Message);
        end
    end
    
    % Rename folders after, inverse list order so that subfolders
    % (datasets) are renamed before their parents (subject folders).
    List = dir(fullfile(BidsFolder, '**', ['*sub-*', OldNamePart, '*']));
    List(~[List.isdir]) = [];
    for f = numel(List):-1:1
        if List(f).isdir
            [IsOk, Message] = movefile(fullfile(List(f).folder, List(f).name), ...
                fullfile(List(f).folder, regexprep(List(f).name, OldExpr(1:end-4), NewExpr(1:end-4)))); % don't include _ses for folders
            if ~IsOk
                error(Message);
            end
        end
    end
    
    % Rename metadata inside BIDS scans.tsv files.
    List = dir(fullfile(BidsFolder, '**', ['*sub-*', NewNamePart, '*_scans.tsv']));
    for f = 1:numel(List)
        ScansFile = fullfile(List(f).folder, List(f).name);
        Fid = fopen(ScansFile, 'r');
        ScansText = fread(Fid, '*char')';
        fclose(Fid);
        if ~isempty(regexp(ScansText, OldExpr, 'once'))
            ScansText = regexprep(ScansText, OldExpr, NewExpr);
            Fid = fopen(ScansFile, 'w');
            fprintf(Fid, '%s', ScansText);
            fclose(Fid);
        end
    end

end