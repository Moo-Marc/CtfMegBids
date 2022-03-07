function [Recordings, Dataset, Message] = BidsRebuildAllFiles(...
        BidsFolder, BidsInfo, BidsDsInfo, KeepFields, Verbose, SaveFiles, ...
        RemoveEmptyFields, RenameFiles, IgnoreInfoMismatch, ContinueFrom, Validate)
    % Rebuild all BIDS metadata files for a CTF MEG dataset (not anatomy yet).
    %
    % If the provided BidsFolder is not the root BIDS folder, only recordings
    % found under the provided folder will be edited.
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
    % If RenameFiles is true (default false), it is possible to change BIDS
    % "entities" that are part of recording file names (but not folder names),
    % by providing them in BidsInfo. Noise or resting state task names will also
    % be standardized as per BIDS in that case. Note that renaming noise
    % recordings may break existing AssociatedEmptyRoom references, but they should
    % be found again and updated.
    %
    % If IgnoreInfoMismatch is true, missing or extra recordings provided in
    % BidsInfo are ignored. 
    %
    % ContinueFrom can be a subject index, a subject name (without "sub-") or
    % "Scans".  This last option skips all recordings and only rebuilds the
    % scans.tsv files based on current recordings.
    %
    % If Validate is true, attempts to run the (external) BIDS validator after
    % running. [needs to be installed and a script path is currently hard coded]
    %
    % An events.json description file is created in the root BIDS folder if
    % there are any events in the dataset. Custom column descriptions can be
    % given in the BidsDsInfo.Events field.
    %
    % Marc Lalancette, 2019 - 2022-02-08
    
    % TODO: Make work if there are missing files.  Probably Verbose fails.
    
    if nargin < 11 || isempty(Validate)
        Validate = false;
    end
    if nargin < 10 || isempty(ContinueFrom)
        ContinueFrom = 1;
    end
    if nargin < 9 || isempty(IgnoreInfoMismatch)
        IgnoreInfoMismatch = false;
    end
    if nargin < 8 || isempty(RenameFiles)
        RenameFiles = false;
    end
    if nargin < 7 || isempty(RemoveEmptyFields)
        RemoveEmptyFields = false;
    end    
    if nargin < 6 || isempty(SaveFiles)
        SaveFiles = true;
    end
    if nargin < 5 || isempty(Verbose)
        Verbose = false;
    end
    if nargin < 4 || isempty(KeepFields)
        KeepFields = struct([]);
    end
    if nargin < 3 || isempty(BidsDsInfo)
        BidsDsInfo = struct([]);
    end
    if nargin < 2 || isempty(BidsInfo)
        BidsInfo = struct([]);
    elseif ~isfield(BidsInfo, 'Name') && any(~isfield(BidsInfo, {'Subject', 'Session', 'Task'}))
        error('BidsInfo should include either Name or at least (Subject, Session, Task) fields to match existing recordings.');
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
    % needed here to regenerate the noise scans.tsv before other recordings (for
    % noise matching).
    
    % Important: only the root level of a struct array must have the same
    % fields, but not the same types (thus not the same subfields). So some
    % subfields may be missing (correctly) if not present in some files, e.g.
    % Recording.Meg.AssociatedEmptyRoom.
    [OldRecordings, Dataset, BidsFolder] = BidsRecordings(BidsFolder, false, true); % not Verbose, NoiseFirst
    nR = numel(OldRecordings);
    
    if ~isempty(ContinueFrom)
        if isnumeric(ContinueFrom)
            iStart = ContinueFrom;
        elseif ischar(ContinueFrom)
            if strcmpi(ContinueFrom, 'scans')
                iStart = inf;
            else
                Subjects = cellfun(@(s)s.Subject, OldRecordings, 'UniformOutput', false);
                iStart = find(strcmp(Subjects, ContinueFrom), 1);
                if isempty(iStart)
                    error('ContinueFrom not found.');
                end
            end
        else
            error('ContinueFrom should be subject name (without sub-) or recording index.');
        end
    else
        iStart = 1;
    end

    
    % --------------------------------------------------------
    % Recordings   
    % Copy some fields from existing metadata files. We must keep BIDS entities that
    % constitute folder and possibly file names since folders are not renamed here
    % and files are also not by default.
    if Verbose
        fprintf('\nFound %d recordings under %s.\n\n', nR, BidsFolder);
    end
    if iStart > nR
        Recordings = OldRecordings;
    else
    KeepRecordings = struct([]);
    FileNameEntities = {'Folder', 'Name', 'Subject', 'Session', 'Task', 'Acq', 'Run'};
    Fields = unique([fieldnames(KeepFields)', FileNameEntities]);
    for f = 1:numel(Fields)
        if isfield(OldRecordings, Fields{f})
            if ismember(Fields{f}, {'Meg', 'CoordSystem'}) && isstruct(KeepFields.(Fields{f}))
                SubFields = fieldnames(KeepFields.(Fields{f}));
                for iSubF = 1:numel(SubFields)
                    % Can't copy in one go with subfields: they aren't consistent.
                    for r = nR:-1:1
                        if isfield(OldRecordings(r).(Fields{f}), SubFields{iSubF})
                            KeepRecordings(r).(Fields{f}).(SubFields{iSubF}) = OldRecordings(r).(Fields{f}).(SubFields{iSubF});
                        end
                    end
                end
            else
                [KeepRecordings(1:nR).(Fields{f})] = OldRecordings.(Fields{f});
            end
        end
    end
    if RenameFiles
        % File renaming allowed, but not folders, do not change sub and ses.
        Fields = setdiff(fieldnames(BidsInfo), FileNameEntities(1:4));
    else
        % No file renaming allowed. And don't keep the matching name.
        Fields = setdiff(fieldnames(BidsInfo), FileNameEntities);
    end
    
    % Order matters here: longer strings should come before substrings, e.g.
    % 'resting' before 'rest'.
    RestSynonyms = {'spontaneous', 'restingstate', 'baselineresting', 'baselinerest', 'restbaseline', 'resting', 'rest'};
    % Add or replace some info if provided.
    if ~isempty(BidsInfo) || RenameFiles
        nMatch = 0;
        nInfo = numel(BidsInfo);
        for r = iStart:nR
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
                        Message{end+1} = sprintf('Automatic noise renaming: %s -> %s, %s\n', KeepRecordings(r).Task, 'noise', KeepRecordings(r).Name);
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
                    ~strcmp(KeepRecordings(r).Task, RestSynonyms{end})
                if RenameFiles
                    if Verbose
                        OldRestName = KeepRecordings(r).Task;
                    end
                    % Standardize resting state task names.  BIDS prescribes: "(for resting state use the rest prefix)"
                    if contains(KeepRecordings(r).Task, RestSynonyms, 'IgnoreCase', true)
                        for iSyn = 1:numel(RestSynonyms)
                            KeepRecordings(r).Task = strrep(KeepRecordings(r).Task, RestSynonyms{iSyn}, '');
                        end
                        KeepRecordings(r).Task = [RestSynonyms{end}, KeepRecordings(r).Task];
                    end
                    if ~strcmp(KeepRecordings(r).Task, OldRestName)
                        Rename = true;
                        if Verbose
                            Message{end+1} = sprintf('Automatic rest renaming: %s -> %s, %s\n', OldRestName, KeepRecordings(r).Task, KeepRecordings(r).Name);
                            fprintf(Message{end});
                        end
                    end
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
                % Only file names are changed, not folders (not sub- or ses-).
                KeepRecordings(r).Name = BidsBuildRecordingName(KeepRecordings(r));
                if SaveFiles
                    % Rename CTF dataset (including files)
                    Bids_ctf_rename_ds(fullfile(BidsFolder, OldRecordings(r).Folder, OldRecordings(r).Name), ...
                        fullfile(BidsFolder, KeepRecordings(r).Folder, KeepRecordings(r).Name));
                    % Rename sidecar files
                    OrigName = OldRecordings(r).Name(1:end-6);
                    NewName = KeepRecordings(r).Name(1:end-6);
                    Files = dir(fullfile(BidsFolder, OldRecordings(r).Folder, [OrigName, '*']));
                    for iFile = 1:length(Files)
                        [isOk, Message] = movefile(fullfile(BidsFolder, OldRecordings(r).Folder, Files(iFile).name), ...
                            fullfile(BidsFolder, KeepRecordings(r).Folder, strrep(Files(iFile).name, OrigName, NewName)));
                        if ~isOk
                            error(Message);
                        end
                    end
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
    
    for r = iStart:nR
        if ~SaveFiles
            % Files not actually renamed so use original.
            Recording = fullfile(BidsFolder, OldRecordings(r).Folder, OldRecordings(r).Name);
        else
            Recording = fullfile(BidsFolder, KeepRecordings(r).Folder, KeepRecordings(r).Name);
        end
        if Verbose
            fprintf('Processing recording %d: %s.\n', r, OldRecordings(r).Name);
        end
        % Need temp struct here because fields are added and struct array assignment needs same fields.
        % Overwrite for recordings applies at the file level.
        TempRec = BidsBuildRecordingFiles(Recording, KeepRecordings(r), Overwrite, SaveFiles, RemoveEmptyFields);
        % Overwrite for session does not replace the file, but the entry.
        % If renamed above, this will add instead of rename, but the extra
        % entries are removed below.
        Recordings(r) = BidsBuildSessionFiles(Recording, TempRec, Overwrite, SaveFiles);
        if r == 1
            % Initialize full structure.
            Recordings(nR, 1) = Recordings(1);
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
        
        % Look for additional coordinate files, e.g. with full recording name.
        % But not for noise recordings (or if for some other reason it's missing).
        if ~isempty(Recordings(r).Files.CoordSystem) 
        CoordFiles = dir(fullfile(BidsFolder, OldRecordings(r).Folder, '*coordsystem.json'));
        if numel(CoordFiles) > 1
            % Should remove extra files.
            for iCoord = 1:numel(CoordFiles)
                CoordFile = fullfile(CoordFiles(iCoord).folder, CoordFiles(iCoord).name);
                if ~strcmp(CoordFile, Recordings(r).Files.CoordSystem)
                    if SaveFiles
                        delete(CoordFile);
                    end
                    if Verbose
                        Message{end+1} = sprintf('    CoordSystem: %s -> %s\n', CoordFile, '(none)');
                        fprintf(Message{end});
                    end
                end
            end
        end
        end
    end
    end % skip recordings
    
    % --------------------------------------------------------
    % Scans tables
    
    % Look for extra scans files, e.g. in subject folder or with wrong
    % name, or extra or duplicate recordings.

    % Make a single table with recordings scan info, including the scans.tsv file names.
    % This doesn't work if there are missing ones.  BidsRecordings modified
    % to never be empty.
    fprintf('\n'); 
    Scans = vertcat(Recordings.Scan); 
    if (iStart <= nR && size(Scans, 1) ~= (nR - iStart + 1)) || (iStart > nR &&  size(Scans, 1) ~= nR)
        error('Unexpected number of scans, maybe BidsBuildSessionFiles problem.');
    end
    ScansFiles = arrayfun(@(x) x.Files.Scans, Recordings, 'UniformOutput', false)';
    OldScansFiles = dir(fullfile(BidsFolder, 'sub-*', '**', '*scans.tsv'));
    %     if Verbose
    %         Message{end+1} = sprintf('Checking for extra scans.\n');
    %         fprintf(Message{end});
    %     end
    for f = 1:numel(OldScansFiles)
        OldScansFile = fullfile(OldScansFiles(f).folder, OldScansFiles(f).name);
        if ~ismember(OldScansFile, ScansFiles)
            % No longer delete, it could be an anatomical session.
            %             if SaveFiles
            %                 delete(OldScansFile);
            %                 Message{end+1} = sprintf('Deleting scans file %s\n', OldScansFile);
            %                 fprintf(Message{end});
            %             elseif Verbose
            if SaveFiles || Verbose
                Message{end+1} = sprintf('Extra scans file: %s\n', OldScansFile);
                fprintf(Message{end});
            end
        elseif SaveFiles || Verbose
            iScans = find(strcmp(OldScansFile, ScansFiles)); % never empty because ismember.
            OldScans = ReadScans(OldScansFile);
            % Check for extras or duplicates, but take into account non-meg
            % (anat) scans.  Dates were already updated and compared above.
            iMeg = strncmp(OldScans.filename, 'meg', 3);
            TempScans = sortrows([Scans(iScans, :); OldScans(~iMeg, :)], {'acq_time', 'filename'});

            if SaveFiles && ( numel(OldScans.filename(iMeg)) ~= numel(iScans) || ...
                    any(~ismember(OldScans.filename(iMeg), Scans.filename(iScans))) )
                % Write sorted in chronological order, include non-meg scans.
                WriteScans(OldScansFile, TempScans);
            end
            if Verbose
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
    
    % --------------------------------------------------------
    % Dataset/Study file
    % Replace some info if provided.
    if ~isfield(BidsDsInfo, 'Dataset')
        % Restructure ("old" way)
        for Field = {'Ignore', 'Files'}
            Field = Field{1}; %#ok<FXSET>
            if isfield(BidsDsInfo, Field)
                BidsDsTemp.(Field) = BidsDsInfo.(Field);
                BidsDsInfo = rmfield(BidsDsInfo, Field);
            end
        end
        BidsDsTemp.Dataset = BidsDsInfo;
        BidsDsInfo = BidsDsTemp;
    end
    if Verbose
        NewMessage = Compare(Dataset, BidsDsInfo, 'Dataset');
        if ~isempty(NewMessage)
            Message{end+1} = sprintf('Manual changes, Dataset\n');
            fprintf(Message{end});
            for m = 1:numel(NewMessage)
                Message{end+1} = NewMessage{m};
                fprintf(Message{end});
            end
        end
    end
    Dataset = UpdateStruct(Dataset, BidsDsInfo);

    % Rebuild and compare.
    OldDataset = Dataset;
    Dataset = BidsBuildStudyFiles(BidsFolder, Dataset, Overwrite, SaveFiles, RemoveEmptyFields);
    if Verbose
        NewMessage = Compare(OldDataset, Dataset, 'Dataset');
        if ~isempty(NewMessage)
            Message{end+1} = sprintf('Automatic changes, Dataset\n');
            fprintf(Message{end});
            for m = 1:numel(NewMessage)
                Message{end+1} = NewMessage{m};
                fprintf(Message{end});
            end
        end
    end
    
    % Optionally validate with external program.
    % (This works on jupiter.)
    if Validate
       Cmd = ['/export02/data/marcl/Software/BidsValidate.sh ', BidsFolder];
       system(Cmd, '-echo');
    end
end

