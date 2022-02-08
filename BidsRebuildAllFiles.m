function [Recordings, Dataset, Message] = BidsRebuildAllFiles(...
        BidsFolder, BidsInfo, BidsDsInfo, KeepFields, Verbose, SaveFiles, ...
        RemoveEmptyFields, RenameFiles, IgnoreInfoMismatch, Validate)
    % Rebuild all BIDS metadata files for a CTF MEG dataset (not anatomy yet).
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
    % If Validate is true, attempts to run the (external) BIDS validator after
    % running. [needs to be installed and a script path is currently hard coded]
    %
    % An events.json description file is created in the root BIDS folder if
    % there are any events in the dataset. Custom column descriptions can be
    % given in the BidsDsInfo.Events field.
    %
    % Marc Lalancette, 2019 - 2021-10-04
    
    %% TODO: Keep existing (e.g. anatomical) entries in scans.tsv!
    % TODO: Make work if there are missing files.  Probably Verbose fails.
    
    if nargin < 10 || isempty(Validate)
        Validate = false;
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
        KeepFields = struct();
    end
    if nargin < 3 || isempty(BidsDsInfo)
        BidsDsInfo = struct();
    end
    if nargin < 2 || isempty(BidsInfo)
        BidsInfo = struct();
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
                    Message{end+1} = sprintf('Manual changes, %s\n', OldRecordings(r).Name);
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
        TempRec = BidsBuildRecordingFiles(Recording, KeepRecordings(r), Overwrite, SaveFiles, RemoveEmptyFields, RenameFiles); 
            % need temp struct here because fields are added and struct array assignment needs same fields.
            % Overwrite for recordings applies at the file level.
        Recordings(r) = BidsBuildSessionFiles(Recording, TempRec, Overwrite, SaveFiles); 
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
            % Compare now takes care of everything including Scan
            %             % Scan
            %             if isempty(OldRecordings(r).Files.Scans)
            %                 Message{end+1} = sprintf('    %s: %s -> %s\n', 'Scans file', '(none)', Recordings(r).Files.Scans);
            %                 fprintf(Message{end});
            %             elseif ~strcmp(OldRecordings(r).Files.Scans, Recordings(r).Files.Scans)
            %                 Message{end+1} = sprintf('    %s: %s -> %s\n', 'Scans file', OldRecordings(r).Files.Scans, Recordings(r).Files.Scans);
            %                 fprintf(Message{end});
            %             end
            %             if isempty(OldRecordings(r).Scan.filename{1})
            %                 Message{end+1} = sprintf('    %s: %s -> %s\n', 'filename', '(none)', Recordings(r).Scan.filename{1});
            %                 fprintf(Message{end});
            %             else
            %                 if ~strcmp(OldRecordings(r).Scan.filename{1}, Recordings(r).Scan.filename{1})
            %                     Message{end+1} = sprintf('    %s: %s -> %s\n', 'filename', OldRecordings(r).Scan.filename{1}, Recordings(r).Scan.filename{1});
            %                     fprintf(Message{end});
            %                 end
            %                 if ~isequal(OldRecordings(r).Scan.acq_time(1), Recordings(r).Scan.acq_time(1))
            %                     Message{end+1} = sprintf('    %s: %s -> %s\n', 'acq_time', OldRecordings(r).Scan.acq_time(1), Recordings(r).Scan.acq_time(1));
            %                     fprintf(Message{end});
            %                 end
            %             end
        end
        
        %         if isfield(OldRecordings(r).Files, CoordSystem) && ~isempty(OldRecordings(r).Files.CoordSystem)
        % Look for additional coordinate files, e.g. with full recording name.        
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
    %     if Verbose
    %         Message{end+1} = sprintf('Checking for extra scans.\n');
    %         fprintf(Message{end});
    %     end
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
                WriteScans(TempScans, OldScansFile);
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
    %     for Field = {'Study', 'License', 'Authors', 'Acknowledgements', ...
    %             'HowToAcknowledge', 'Funding', 'ReferencesAndLinks', 'DatasetDOI'}
    %         Field = Field{1}; %#ok<FXSET>
    %         if isfield(BidsDsInfo, Field)
    %             if Verbose
    %                 New = struct();
    %                 New.(Field) = BidsDsInfo.(Field);
    %             end
    %                 && any(Dataset.Dataset.(Field) ~= BidsDsInfo.(Field))
    %                 Message{end+1} = sprintf(OutFormat, Field, AutoSprintf(Dataset.Dataset.(Field)), AutoSprintf(BidsDsInfo.(Field)));
    %                 fprintf(Message{end});
    %             end
    %             Dataset.Dataset.(Field) = BidsDsInfo.(Field);
    %         end
    %     end
    %     if isfield(BidsDsInfo, 'Ignore')
    %         if Verbose
    %             if ~isfield(Dataset, 'Files') || ~isfield(Dataset.Files, 'Ignore')
    %                 Message{end+1} = sprintf(OutFormat, 'Ignore', '(none)', AutoSprintf(BidsDsInfo.Ignore));
    %                 fprintf(Message{end});
    %             elseif ~isempty(setxor(Dataset.Ignore, BidsDsInfo.Ignore))
    %                 Message{end+1} = sprintf(OutFormat, 'Ignore', AutoSprintf(Dataset.Ignore), AutoSprintf(BidsDsInfo.Ignore));
    %                 fprintf(Message{end});
    %             end
    %         end
    %         Dataset.Ignore = BidsDsInfo.Ignore;
    %     end
    
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
        %         for Field = fieldnames(Dataset.Dataset)'
        %             Field = Field{1}; %#ok<FXSET>
        %             if any(OldDataset.Dataset.(Field) ~= Dataset.Dataset.(Field))
        %                 Message{end+1} = sprintf('    %s: %s -> %s\n', Field, OldDataset.Dataset.(Field), Dataset.Dataset.(Field));
        %                 fprintf(Message{end});
        %             end
        %         end
        %         if isfield(Dataset, 'Files') && isfield(Dataset.Files, 'Ignore') && ...
        %                 (~isfield(OldDataset, 'Files') || ~isfield(OldDataset.Files, 'Ignore'))
        %             Message{end+1} = sprintf('    %s: %s -> %s\n', 'Ignore', '(none)', AutoSprintf(Dataset.Ignore));
        %             fprintf(Message{end});
        %         elseif ~isempty(setxor(OldDataset.Ignore, Dataset.Ignore))
        %             Message{end+1} = sprintf('    %s: %s -> %s\n', 'Ignore', AutoSprintf(OldDataset.Ignore), AutoSprintf(Dataset.Ignore));
        %             fprintf(Message{end});
        %         end
    end
    
    % Optionally validate with external program.
    % (This works on jupiter.)
    if Validate
       Cmd = ['/export02/data/marcl/Software/BidsValidate.sh ', BidsFolder];
       system(Cmd, '-echo');
    end
end

