function Extras = DsToBids(Recording, Destination, BidsInfo, Anonymize, ...
        ExtrasFolder, iLog)
    % Convert single CTF recording and adjoining files to BIDS structure.
    %
    % Extras = DsToBids(Recording, Destination, BidsInfo, Anonymize, ...
    %     ExtrasFolder)
    %
    % Inputs:
    %   Recording: Original CTF .ds folder.
    %   Destination: Base folder where BIDS subject folder is to be created.
    %   BidsInfo: Structure with fields Subject, Session, Task, and
    %   optionally Acq, Run, Study, Ignore all strings, not numerical types. 
    %   BidsInfo.Ignore is a list of file types to ignore when validating
    %   the BIDS dataset, e.g. {'*.log'}.  If not empty, it
    %   creates the .bidsignore file in Destination.
    %   Anonymize [default false]: If true, remove all identifying
    %   information from recording.
    %   ExtrasFolder [default []]: Where to store "extra" files not part of
    %   the raw recording, like session logs and pictures.  If empty, they 
    %   will be stored in the BIDS meg folder,
    %   <Destination>/sub-xxxx/ses-xxxx/meg, with the recording.  Otherwise,
    %   <ExtrasFolder>/sub-xxxx/ses-xxxx/extras.
    %   iLog: Matlab file id of a log file where to output messages instead of screen.
    %
    % Output:
    %   Extras: List of additional files found and stored in ExtrasFolder.
    %
    % If Recording is already in a BIDS structure, sidecar files are ignored and
    % recreated in the destination, if they don't exist there.  If the recording
    % is not found but it already exists in the destination, we look for
    % additional files that may have been missed.  Otherwise, if it is missing
    % or it already exists in the destination, a warning is issued and we don't
    % proceed.
    %
    % Marc Lalancette, 2021-04-21
    
    % Tested on linux.
    
    % TODO: option to overwrite existing metadata files in destination.
    
    if nargin < 3
        error('Not enough inputs.');
    end
    if nargin < 6 || isempty(iLog)
        iLog = 1;
    end
    if nargin < 5
        ExtrasFolder = [];
    end
    if nargin < 4 || isempty(Anonymize)
        Anonymize = false;
    end
    if ~all(isfield(BidsInfo, {'Subject', 'Session', 'Task'}))
        error('Missing BIDS info.');
    end
    
    [DsFolder, DsName, DsExt] = fileparts(Recording);
    if ~strcmpi(DsExt, '.ds')
        error('CTF recording expected.');
    end
    [DsSubject, DsNameRem] = strtok(DsName, '_');
    % If already BIDS format, all files will start with sub-xxxx_ses-xxxx.
    DsSession = strtok(DsNameRem, '_');
    if ~strncmp(DsSession, 'ses-', 4)
        DsSession = '';
    else
        DsSession = ['_', DsSession];
    end
    % Special case for noise recordings.
    if strcmpi(BidsInfo.Subject, 'emptyroom') && ~contains(DsSubject, 'emptyroom')
        DsSubject = 'emptyroom';
    end
    % Check for same old and new subject name.
    if strcmp(DsSubject, BidsInfo.Subject)
        DiffNewSubject = false;
    else
        DiffNewSubject = true;
    end
    % Check for additional "wrong" subject name, provided by MegToOmegaBids
    % which reads a spreadsheet of recordings.
    if isfield(BidsInfo, 'WrongSubject') && ~isempty(BidsInfo.WrongSubject)
        WrongSubject = true;
    else
        WrongSubject = false;
    end
    
    fprintf(iLog, '  Converting to BIDS: %s\n', DsName);
    % Rename and move each recording.
    % sub-<participant_label>[_ses-<label>]_task-<task_label>
    %   [_acq-<label>][_run-<index>][_proc-<label>]_meg.ds
    
    % Create directory structure.
    NewFolder = fullfile(Destination, ['sub-', BidsInfo.Subject], ...
        ['ses-', BidsInfo.Session], 'meg');
    if ~exist(NewFolder, 'dir')
        mkdir(NewFolder);
    end
    if isempty(ExtrasFolder)
        ExtrasFolder = NewFolder;
    else
        ExtrasFolder = fullfile(ExtrasFolder, ['sub-', BidsInfo.Subject], ...
            ['ses-', BidsInfo.Session], 'extras');
    end
    
    NewName = ['sub-', BidsInfo.Subject, '_ses-', BidsInfo.Session, '_task-', BidsInfo.Task];
    if isfield(BidsInfo, 'Acq') && ~isempty(BidsInfo.Acq)
        NewName = [NewName, '_acq-', BidsInfo.Acq]; %#ok<*AGROW>
    end
    if isfield(BidsInfo, 'Run') && ~isempty(BidsInfo.Run)
        NewName = [NewName, '_run-', BidsInfo.Run]; % string
    end
    NewName = [NewName, '_meg.ds'];
    
    if ~exist(Recording, 'dir') && exist(fullfile(NewFolder, NewName), 'dir')
        fprintf(iLog, '  Recording already converted, looking for extras only.\n');
    else
        if ~exist(Recording, 'dir')
            fprintf(iLog, '  Warning: Recording not found.\n');
            return;
        elseif exist(fullfile(NewFolder, NewName), 'dir')
            fprintf(iLog, '  Warning: Destination already exists, ignoring.\n');
            return;
        end
        
        % Modified Brainstorm function: ctf_rename_ds
        Bids_ctf_rename_ds(Recording, NewName, NewFolder, Anonymize) 
    end
    
    
    % Deal with session log, pos file and jpeg pictures outside and inside
    % recording folder.
    
    % Keep track of all these "extra" files.
    Extras = {};
    
    % Rename the session log.
    % List them, then find the one(s) with the correct subject ID.
    SessLogs = dir(fullfile(DsFolder, [BidsInfo.Subject, '*sessionLog*']));
    if DiffNewSubject
        SessLogs = [ SessLogs; dir(fullfile(DsFolder, [DsSubject, '*sessionLog*'])) ];
    end
    if WrongSubject
        SessLogs = [ SessLogs; dir(fullfile(DsFolder, [BidsInfo.WrongSubject, '*sessionLog*'])) ];
    end
    % Also look for session log files inside the recording folder.
    SessLogs = [SessLogs; dir(fullfile(NewFolder, NewName, '*sessionLog*'))];
    NewSessLog = ['sub-', BidsInfo.Subject, '_ses-', BidsInfo.Session, '_sessionLog.log'];
    NewSessLogBak = ['sub-', BidsInfo.Subject, '_ses-', BidsInfo.Session, '_sessionLog.log.bak'];
    for p = 1:numel(SessLogs)
        % No longer delete backups or empty files.
        if strcmpi(SessLogs(p).name(end-3:end), '.bak')
            CurrentSessLogBak = dir(fullfile(ExtrasFolder, NewSessLogBak));
            if exist(fullfile(ExtrasFolder, NewSessLogBak), 'file') && ...
                    CurrentSessLogBak.bytes >= SessLogs(p).bytes
                % Delete duplicates.
                delete(fullfile(SessLogs(p).folder, SessLogs(p).name));
            else
                % Move.
                if ~exist(ExtrasFolder, 'dir')
                    mkdir(ExtrasFolder);
                end
                Extras{end+1} = fullfile(ExtrasFolder, NewSessLogBak);
                [Status, Msg] = movefile( ...
                    fullfile(SessLogs(p).folder, SessLogs(p).name), ...
                    Extras{end} );
                if ~Status
                    fprintf(iLog, [Msg, '\n']);
                end
            end
        else % not .log.bak file
            CurrentSessLog = dir(fullfile(ExtrasFolder, NewSessLog));
            if exist(fullfile(ExtrasFolder, NewSessLog), 'file') && ...
                    CurrentSessLog.bytes >= SessLogs(p).bytes
                % Delete duplicates.
                delete(fullfile(SessLogs(p).folder, SessLogs(p).name));
            else
                % Move.
                if ~exist(ExtrasFolder, 'dir')
                    mkdir(ExtrasFolder);
                end
                Extras{end+1} = fullfile(ExtrasFolder, NewSessLog);
                [Status, Msg] = movefile( ...
                    fullfile(SessLogs(p).folder, SessLogs(p).name), ...
                    Extras{end} );
                if ~Status
                    fprintf(iLog, [Msg, '\n']);
                end
            end
        end
    end % .log file loop
    
    % Rename the .jpg files.
    Pics = dir(fullfile(DsFolder, [BidsInfo.Subject, '*.jpg']));
    Pics = [ Pics; dir(fullfile(DsFolder, [BidsInfo.Subject, '*.JPG'])) ];
    if DiffNewSubject
        Pics = [ Pics; dir(fullfile(DsFolder, [DsSubject, '*.jpg'])) ];
        Pics = [ Pics; dir(fullfile(DsFolder, [DsSubject, '*.JPG'])) ];
    end
    if WrongSubject
        Pics = [ Pics; dir(fullfile(DsFolder, [BidsInfo.WrongSubject, '*.jpg'])) ];
        Pics = [ Pics; dir(fullfile(DsFolder, [BidsInfo.WrongSubject, '*.JPG'])) ];
    end
    %     if isempty(Pics) && isempty(dir(fullfile(ExtrasFolder, '*.jpg')))
    %         fprintf(iLog, '  No pictures found.\n');
    %     end
    for p = 1:numel(Pics)
        if ~exist(ExtrasFolder, 'dir')
            mkdir(ExtrasFolder);
        end
        Extras{end+1} = fullfile(ExtrasFolder, ['sub-', BidsInfo.Subject, ...
            '_ses-', BidsInfo.Session, '_acq-', sprintf('%02d', p), '_photo', '.jpg']);
        [Status, Msg] = movefile( ...
            fullfile(Pics(p).folder, Pics(p).name), ...
            Extras{end} );
        if ~Status
            fprintf(iLog, [Msg, '\n']);
        end
    end % .jpg file loop
    
    % Rename the .pos file(s).
    % List them, then find the one(s) with the correct subject ID.
    PosFile = dir(fullfile(DsFolder, [BidsInfo.Subject, '*.pos']));
    if DiffNewSubject
        PosFile = [ PosFile; dir(fullfile(DsFolder, [DsSubject, '*.pos'])) ];
    end
    if WrongSubject
        PosFile = [ PosFile; dir(fullfile(DsFolder, [BidsInfo.WrongSubject, '*.pos'])) ];
    end
    % Also look for head shape files inside the recording folder.
    PosFile = [PosFile; dir(fullfile(NewFolder, NewName, '*.pos'))];
    NewHeadShape = ['sub-', BidsInfo.Subject, '_ses-', BidsInfo.Session, '_headshape.pos'];
    NewElectrodes = ['sub-', BidsInfo.Subject, '_ses-', BidsInfo.Session, '_acq-electrodes_headshape.pos'];
    for p = 1:numel(PosFile)
        if contains(PosFile(p).name, 'eeg', 'IgnoreCase', true) || ...
                contains(PosFile(p).name, 'elec', 'IgnoreCase', true)
            NewPosFile = NewElectrodes;
        else
            NewPosFile = NewHeadShape;
        end
        KeptPosFile = dir(fullfile(NewFolder, NewPosFile));
        if ~isempty(KeptPosFile)
            % Delete duplicates. Verify size is same otherwise just leave it.  It
            % will be renamed with "other files" later unless it's in the ds folder.
            if PosFile(p).bytes == KeptPosFile(1).bytes
                delete(fullfile(PosFile(p).folder, PosFile(p).name));
            end
        else
            % Move.
            % Head shape file is not considered an "extra".
            %Extras{end+1} = fullfile(NewFolder, NewHeadShape);
            [Status, Msg] = movefile( ...
                fullfile(PosFile(p).folder, PosFile(p).name), ...
                fullfile(NewFolder, NewPosFile) );
            if ~Status
                fprintf(iLog, [Msg, '\n']);
            end
        end
    end % .pos file loop
    
    % Rename other files that start with the subject ID (e.g. log files).
    OtherFiles = dir(fullfile(DsFolder, [BidsInfo.Subject, '*']));
    if DiffNewSubject
        OtherFiles = [ OtherFiles; dir(fullfile(DsFolder, [DsSubject, '*'])) ];
    end
    if WrongSubject
        OtherFiles = [ OtherFiles; dir(fullfile(DsFolder, [BidsInfo.WrongSubject, '*'])) ];
    end
    for p = 1:numel(OtherFiles)
        % Need to avoid other datasets and folders.  Also ignore BIDS sidecar
        % files as they will be recreated.  DsSubject was changed to emptyroom
        % if noise recording so other files won't be found here.
        if strcmpi(OtherFiles(p).name(end-2:end), '.ds') || ...
                OtherFiles(p).isdir || ...
                strcmpi(OtherFiles(p).name(end-3:end), '.tsv') || ...
                strcmpi(OtherFiles(p).name(end-4:end), '.json')
            continue;
        end
        % Replace subject and potentially session ID.
        NewOtherFile = strrep(OtherFiles(p).name, [DsSubject, DsSession], ...
            ['sub-', BidsInfo.Subject, '_ses-', BidsInfo.Session]);
        if WrongSubject
            NewOtherFile = strrep(NewOtherFile, [BidsInfo.WrongSubject, DsSession], ...
                ['sub-', BidsInfo.Subject, '_ses-', BidsInfo.Session]);
        end
        if exist(fullfile(ExtrasFolder, NewOtherFile), 'file')
            % Delete duplicates.
            delete(fullfile(OtherFiles(p).folder, OtherFiles(p).name));
        else
            % Move.
            if ~exist(ExtrasFolder, 'dir')
                mkdir(ExtrasFolder);
            end
            Extras{end+1} = fullfile(ExtrasFolder, NewOtherFile);
            [Status, Msg] = movefile( ...
                fullfile(OtherFiles(p).folder, OtherFiles(p).name), ...
                Extras{end} );
            if ~Status
                fprintf(iLog, [Msg, '\n']);
            end
        end
    end % file loop
    
    % Remove empty source folder.
    RemainingFiles = dir(DsFolder);
    if ~isempty(RemainingFiles)
        % Implies folder exists.
        RemainingFiles(strcmpi({RemainingFiles.name}, '.')) = [];
        RemainingFiles(strcmpi({RemainingFiles.name}, '..')) = [];
        if isempty(RemainingFiles) % && exist(DsFolder, 'dir')
            [Status, Msg] = rmdir(DsFolder);
            if ~Status
                fprintf(iLog, [Msg, '\n']);
            end
        end
    end
    
    % Build BIDS metadata files.
    % Do study files first since BidsRecordings looks for BIDS root folder.
    % BidsBuildStudyFiles(BidsFolder, BidsInfo, Overwrite, SaveFiles, RemoveEmptyFields, isEvents)
    BidsBuildStudyFiles(Destination, BidsInfo); 
    % BidsBuildRecordingFiles(Recording, BidsInfo, Overwrite, SaveFiles, RemoveEmptyFields, iLog)
    BidsBuildRecordingFiles(fullfile(NewFolder, NewName), BidsInfo); 
    % BidsBuildSessionFiles(Recording, BidsInfo, Overwrite, SaveFiles)
    BidsBuildSessionFiles(fullfile(NewFolder, NewName), BidsInfo); 
        
end
