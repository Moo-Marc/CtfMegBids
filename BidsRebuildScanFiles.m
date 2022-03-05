function [Recordings, Dataset, Message] = BidsRebuildScanFiles(...
        BidsFolder, Verbose, SaveFiles)
    % Rebuild BIDS scans.tsv files.
    %
    % BidsFolder must be the root study folder, not a subject or session
    % for example.
    %
    % Recreates BIDS metadata files from potentially 3 sources.  In order of
    % priority: 
    %  1) Data manually provided in BidsInfo and BidsDsInfo structures, this is
    %  matched by recording using the BidsInfo.Name (file name only with .ds)
    %  field. Since this script does not rename folders, it is not possible to
    %  change the BIDS "entities" that constitute folder names (subject ID and
    %  session ID).
    %
    %  2) Data in existing recording (not session or dataset) BIDS metadata
    %  files according to the KeepFields structure, which does not need to
    %  contain any data but only part of the field structure as returned by
    %  BidsRecordings. I.e. a subset of: KeepFields.Meg and the first level of
    %  sub-fields from the _meg.json file, KeepFields.Coordsys and the first
    %  level of sub-fields from the _coordsys.json file, .Channels (no
    %  sub-fields), and .Events (no sub-fields).
    %
    %  3) The metadata extracted from the raw data files.
    %
    % If SaveFiles is false (default true), no files are modified.  This can be
    % used with Verbose = true to perform a dry run and see in details what
    % would get changed.
    %
    % Marc Lalancette, 2019 - 2021-10-04
    
    %% TODO
    error('WIP');

    if nargin < 3 || isempty(SaveFiles)
        SaveFiles = true;
    end
    if nargin < 2 || isempty(Verbose)
        Verbose = false;
    end
    if nargin < 1 || isempty(BidsFolder)
        error('BidsFolder input required.')
    end
    
    if SaveFiles
        Overwrite = true;
    else
        Overwrite = false;
    end
    
    OutFormat = '    %s: %s -> %s\n';
    Message = {};
    if ~SaveFiles
        Message{end+1} = sprintf('\n----- Dry run selected.  No files will be modified. -----\n');
        fprintf(Message{end});
    end
    
    % First get the old metadata. Returns noise recordings first, which is
    % needed here to regenerate the noise scans.tsv before other
    % recordings (for noise matching).
    [OldRecordings, Dataset] = BidsRecordings(BidsFolder, false, true); % not Verbose, NoiseFirst
    nR = numel(OldRecordings);
    
    % --------------------------------------------------------
    % Recordings   
    % Copy some fields from existing metadata files. We must keep BIDS entities that
    % constitute folder and possibly file names since folders are not renamed here
    % and files are also not by default.
    KeepRecordings = struct();
    FileNameEntities = {'Folder', 'Name', 'Subject', 'Session', 'Task', 'Acq', 'Run'};
    Fields = unique([fieldnames(KeepFields), FileNameEntities]);
    for f = 1:numel(Fields)
        if isfield(OldRecordings, Fields{f})
            [KeepRecordings(1:nR).(Fields{f})] = OldRecordings.(Fields{f});
        end
    end
    if RenameFiles
        % File renaming allowed, but not folders, do not change sub and ses.
        Fields = setdiff(fieldnames(BidsInfo), FileNameEntities(1:4));
    else
        % No file renaming allowed. And don't keep the matching name.
        Fields = setdiff(fieldnames(BidsInfo), FileNameEntities);
    end
    
    RestSynonyms = {'Spontaneous', 'Restingstate', 'Baselinerest', 'Resting', 'Rest', ...
        'spontaneous', 'restingstate', 'baselinerest', 'resting', 'rest'};
    % Add or replace some info if provided.
    if ~isempty(BidsInfo) || RenameFiles
        nMatch = 0;
        nInfo = numel(BidsInfo);
        for r = 1:nR
            % Find matching new info.
            iInfo = 0;
            for q = 1:nInfo
                if isfield(BidsInfo, 'Name')
                    Name = BidsInfo(q).Name;
                    if contains(Name, filesep)
                        error('BidsInfo.Name should not contain the path.'); % since in a loop a warning would appear many times.
                        %[~, Name, Ext] = fileparts(BidsInfo(q).Name);
                        %Name = [Name, Ext];
                    end
                else % not the recommended way to match existing recordings, but try with individual entities.
                    Name = BidsBuildRecordingName(BidsInfo(q));
                end
                if strcmp(OldRecordings(r).Name, Name)
                    iInfo = q;
                    nMatch = nMatch + 1;
                    break;
                end
            end
            if iInfo
                if Verbose
                    Message{end+1} = sprintf('Manual changes, %s\n', OldRecordings(r).Name); %#ok<*AGROW> 
                    fprintf(Message{end});
                end
                for f = 1:numel(Fields)
                    Field = Fields{f};
                    if Verbose
                        Message{end+1} = sprintf(OutFormat, Field, OldRecordings(r).(Field), BidsInfo(iInfo).(Field));
                        fprintf(Message{end});
                    end
                    KeepRecordings(r).(Field) = BidsInfo(iInfo).(Field);
                end
                if RenameFiles
                    % Rebuild name in case it should change.
                    KeepRecordings(r).Name = BidsBuildRecordingName(KeepRecordings(r));
                end
            end
    
            % Warn or rename if non-standard names.
            % File name entities were kept.
            Rename = false;
            % Check noise task name
            if (contains(KeepRecordings(r).Subject, 'emptyroom') || strncmpi(KeepRecordings(r).Task, 'noise', 5)) && ...
                    ~strcmp(KeepRecordings(r).Task, 'noise')
                if RenameFiles
                    if Verbose
                        Message{end+1} = sprintf('Automatic noise renaming: %s -> %s\n', KeepRecordings(r).Task, 'noise');
                        fprintf(Message{end});
                    end
                    KeepRecordings(r).Task = 'noise';
                    Rename = true;
                else
                    % Warn even if not Verbose
                    Message{end+1} = sprintf('Warning: Non-standard noise recording task name: %s', KeepRecordings(r).Name);
                    fprintf(Message{end});
                end
            end
            % Check rest task name
            if contains(KeepRecordings(r).Task, RestSynonyms, 'IgnoreCase', true) && ...
                    ~strncmp(KeepRecordings(r).Task, RestSynonyms{end}, numel(RestSynonyms{end}))
                if RenameFiles
                    % Standardize resting state task names.  BIDS prescribes: "(for resting state use the rest prefix)"
                    if contains(KeepRecordings(r).Task, RestSynonyms, 'IgnoreCase', true)
                        for iSyn = 1:numel(RestSynonyms)-1
                            KeepRecordings(r).Task = strrep(KeepRecordings(r).Task, RestSynonyms{iSyn}, '');
                        end
                        KeepRecordings(r).Task = [RestSynonyms{end}, KeepRecordings(r).Task];
                    end
                    Rename = true;
                else
                    % Warn even if not Verbose
                    Message{end+1} = sprintf('Warning: Likely non-standard resting state recording task name, should start with ''rest'': %s', KeepRecordings(r).Name);
                    fprintf(Message{end});
                end
            end
            % Check acq other than "AUX"
            if isfield(KeepRecordings, 'acq') && ~isempty(KeepRecordings(r).Acq) && ...
                    ~strcmpi(KeepRecordings(r).Acq, 'AUX')
                if RenameFiles
                    KeepRecordings(r).Acq = '';
                    Rename = true;
                else
                    % Warn even if not Verbose
                    Message{end+1} = sprintf('Warning: Unknown use of the acq entity for MEG: %s', KeepRecordings(r).Name);
                    fprintf(Message{end});
                end
            end
            if Rename
                KeepRecordings(r).Name = BidsBuildRecordingName(KeepRecordings(r));
                % Rename CTF dataset (including files)
                Bids_ctf_rename_ds(fullfile(OldRecordings(r).Folder, OldRecordings(r).Name), ...
                    fullfile(KeepRecordings(r).Folder, KeepRecordings(r).Name));
                % Rename sidecar files
                OrigName = OldRecordings(r).Name(1:end-6);
                NewName = KeepRecordings(r).Name(1:end-6);
                Files = dir(fullfile(OldRecordings(r).Folder, [OrigName, '*']));
                for iFile = 1:length(Files)
                    movefile(fullfile(OldRecordings(r).Folder, Files(iFile).name), ...
                        fullfile(KeepRecordings(r).Folder, strrep(Files(iFile).name, OrigName, NewName)));
                end
            end
            
        end % recording loop
        if nMatch < nInfo && ~IgnoreInfoMismatch
            % Probably best to not proceed if possible mismatch.
            error('Some provided BIDS info did not match any existing recordings.');
        end
    end

    
    % Rebuild and compare, including scans tables.
    %     Recordings = [];
    %     Recordings(nR) = struct('Name', '', 'Folder', '', 'Subject', '', 'Session', '', ...
    %         'Task', '', 'Acq', '', 'Run', '', 'Scan', struct('AcqDate', datetime()), ...
    %         'Meg', struct(), 'CoordSystem', struct(), 'Channels', table(), 'Files', struct());
    %     Recordings(nR) = struct('Subject', '', 'Session', '', 'Task', '', ...
    %         'Meg', struct(), 'CoordSystem', struct(), 'Channels', table(), 'Files', struct());
    for r = 1:nR 
        Recording = fullfile(BidsFolder, OldRecordings(r).Folder, OldRecordings(r).Name);
        if Verbose
            fprintf('Processing recording %d: %s.\n', r, Recording);
        end
        Recordings(r) = BidsBuildSessionFiles(Recording, [], Overwrite, SaveFiles); 
            % Overwrite for session does not replace the file, but the entry.
        if r == 1
            % Initialize full structure.
            Recordings(nR) = Recordings(1);
        end
        if Verbose
            NewMessage = Compare(OldRecordings(r), Recordings(r), sprintf('Recordings(%d)', r));
            if ~isempty(NewMessage)
                Message{end+1} = sprintf('All changes, %s\n', Recordings(r).Name);
                fprintf(Message{end});
                for m = 1:numel(NewMessage)
                    Message{end+1} = NewMessage{m};%     Scans = vertcat(Recordings.Scan); % This doesn't work if there are missing ones.
                    fprintf(Message{end});
                end
            end
        end
    end
        
    % --------------------------------------------------------
    % Scans tables
    
    % Look for extra scans files, e.g. in subject folder or with wrong
    % name, or extra or duplicate recordings.

    % Make a single table with recordings scan info, including the scans.tsv file names.
    % This doesn't work if there are missing ones.  BidsRecordings modified
    % to never be empty.
    Scans = vertcat(Recordings.Scan); 
    if size(Scans, 1) ~= nR
        error('Unexpected number of scans, maybe BidsBuildSessionFiles problem.');
    end
    ScansFiles = arrayfun(@(x) x.Files.Scans, Recordings, 'UniformOutput', false)';
    OldScansFiles = dir(fullfile(BidsFolder, '**', '*scans.tsv'));
    for f = 1:numel(OldScansFiles)
        OldScansFile = fullfile(OldScansFiles(f).folder, OldScansFiles(f).name);
        if ~ismember(OldScansFile, ScansFiles)
            if SaveFiles
                delete(OldScansFile);
                Message{end+1} = sprintf('Deleting scans file %s\n', OldScansFile);
                fprintf(Message{end});
            elseif Verbose
                Message{end+1} = sprintf('Extra scans file: %s\n', OldScansFile);
                fprintf(Message{end});
            end
        else
            iScans = find(strcmp(OldScansFile, ScansFiles)); % never empty because ismember.
            OldScans = ReadScans(OldScansFile);
            % Check for extras or duplicates.  Dates were already updated
            % and compared above.
            if SaveFiles && ( numel(OldScans.filename) ~= numel(iScans) || ...
                    any(~ismember(OldScans.filename, Scans.filename(iScans))) )
                % Write sorted in chronological order.  This means a file may
                % get saved without verbose indicating any changes.
                WriteScans(OldScansFile, TempScans);
            end
            if Verbose
                % Sort in chronological order for comparison.
                TempScans = sortrows(Scans(iScans, :), {'acq_time', 'filename'});
                OldScans.acq_time = StrToDatetime(OldScans.acq_time);
                NewMessage = Compare(OldScans, TempScans, 'Scans');
                if ~isempty(NewMessage)
                    Message{end+1} = sprintf('Extra or duplicate scans, %s\n', OldScansFile);
                    fprintf(Message{end});
                    for m = 1:numel(NewMessage)
                        Message{end+1} = NewMessage{m};
                        fprintf(Message{end});
                    end
                end
            end
        end
    end
    
end

