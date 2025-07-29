function PosRenameFids(PosFile)
    % Rename digitized anat fids to head coils (HPI) if the latter are missing, after backing up pos file.
    % Should normally run in BIDS dataset, with backup saved under sourcedata, but works either way.

    % Re-import that .pos file. This converts to "Native" CTF coil-based coordinates if coils present,
    % or SCS, which in this case is actually "Native" and coordinates will be correct after renaming.
    Pos = in_channel_pos(PosFile);
    % Check that no coils are present, but anat
    iAnatomical = find(strcmp(Pos.HeadPoints.Type, 'CARDINAL'), 1);
    iHeadCoils = find(ismember(Pos.HeadPoints.Type, {'HPI','HLU'}), 1);
    if ~isempty(iHeadCoils)
        warning('Digitized head coils already present, but asked to rename anat fids. Aborting. %s', PosFile);
        return;
    elseif isempty(iAnatomical)
        warning('No anatomical fiducials found, but asked to rename them. Aborting. %s', PosFile);
        return;
    end
        
    % Create sourcedata folder for this session. 
    [PosPath, PosName, PosExt] = fileparts(PosFile);
    iRelativePath = strfind(PosPath, [filesep, 'sub-']);
    if isempty(iRelativePath) 
        % Not BIDS, keep full path; but should not happen as this function should run after moving
        % to BIDS folder structure.
        iRelativePath = numel(PosPath) + 1; 
    end
    BidsFolder = PosPath(1:iRelativePath(1)-1);
    BakFolder = replace(PosPath, BidsFolder, fullfile(BidsFolder, 'sourcedata'));
    if ~exist(BakFolder, 'dir')
        [isOk, Msg] = mkdir(BakFolder);
        if ~isOk, warning(Msg); end
    end
    if ~exist(BakFolder, 'dir')
        warning('Unable to create backup folder %s.', BakFolder);
        return;
    end
    % Save backup if doesn't already exist.
    BakFile = replace([PosName PosExt], '_headshape.pos', '_acq-orig_headshape.pos');
    BakFile = fullfile(BakFolder, BakFile);
    if ~exist(BakFile, 'file')
        [isOk, Msg] = copyfile(PosFile, BakFile);
        if ~isOk, warning(Msg); end
        if ~exist(BakFile, 'file')
            warning('Unable to back up file %s.', BakFile);
            return;
        end
    end

    % Rename anat fids as head coils (head position indicators HPI)
    RenameCount = 0;
    isFid = ismember(Pos.HeadPoints.Label, {'NAS', 'Nasion', 'nasion'});
    RenameCount = RenameCount + sum(isFid);
    Pos.HeadPoints.Label(isFid) = {'HPI-N'};
    Pos.HeadPoints.Type(isFid) = {'HPI'};
    isFid = ismember(Pos.HeadPoints.Label, {'LPA', 'left'});
    RenameCount = RenameCount + sum(isFid);
    Pos.HeadPoints.Label(isFid) = {'HPI-L'};
    Pos.HeadPoints.Type(isFid) = {'HPI'};
    isFid = ismember(Pos.HeadPoints.Label, {'RPA', 'right'});
    RenameCount = RenameCount + sum(isFid);
    Pos.HeadPoints.Label(isFid) = {'HPI-R'};
    Pos.HeadPoints.Type(isFid) = {'HPI'};

    % Check for unknown leftover anat fids
    iAnatomical = find(strcmp(Pos.HeadPoints.Type, 'CARDINAL'));
    if ~isempty(iAnatomical)
        warning('%d unknown anatomical fiducials leftover after renaming: %s. %s', ...
            numel(iAnatomical), Pos.HeadPoints.Label{iAnatomical(1)}, PosFile);
    end
    % Save fixed file with backup
    FixedFile = replace(BakFile, '_acq-orig', '_acq-renamehpi');
    % This does not transform coordinates from channel file, but converts to cm.
    out_channel_pos(Pos, FixedFile);
    if ~exist(FixedFile, 'file')
        warning('Unable to save fixed file %s.', FixedFile);
        % Still continue and allow overwriting main file since we have a backup.
        out_channel_pos(Pos, PosFile);
    else
        % Overwrite main pos.
        [isOk, Msg] = copyfile(FixedFile, PosFile);
        if ~isOk, warning(Msg); end
    end

    fprintf('Renamed %d anatomical fiducials as HPI in %s\n', RenameCount, PosFile);
end
