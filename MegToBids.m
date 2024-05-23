function MegToBids(AcqDateFolder, Destination, UseSubEmptyroom, SaveLog, StudyName, BidsOverwrite)
    % Find all CTF recordings in a folder and convert them to BIDS structure.
    %
    % MegToBids(AcqDateFolder, UseSubEmptyroom, StudyName, BidsOverwrite)
    %
    % Inputs:
    %  AcqDateFolder: Folder to search for datasets, including subfolders.
    %   StudyName [default empty]: Optional name of the study, saved in a BIDS
    %   sidecar file only.
    %  Destination: BIDS root folder where to move the recordings to. If not
    %   provided, the BIDS data are saved in the parent of AcqDateFolder.
    %   AcqDateFolder is deleted if empty at the end of the conversion.
    %  UseSubEmptyroom [default false]: If true, put all empty room noise
    %   recordings under subject sub-emptyroom, with dates as sessions.
    %   Otherwise, kept under corresponding subject folders. (The latter is more
    %   convenient for per-subject noise collections and eventual date
    %   anonymization, even though the BIDS standard suggests the former.)
    %  SaveLog [default false]: If true, outputs errors, warnings and
    %   information about conversion to a log file instead of the screen.
    %  BidsOverwrite [default empty]: Fields in this structure array will
    %   overwrite those extracted from the recording name (e.g. Subject,
    %   Session, Task, etc.).  To ensure that the array aligns with the
    %   recordings, there must be a field called Recording with the recording
    %   name (no path, but including .ds).  If BidsOverwrite.Session = 'Date',
    %   the scan date will be used (yyyymmdd).
    %
    % Recognized recording name formats: BIDS, CTF.
    %
    % This function can be called from the command line and used in a cron job
    % for example.
    %
    % Marc Lalancette, 2021-11-26
    
    % TO DO: Session is optional in BIDS standard, now we use the date when
    % missing.  Should allow no session.
    
    % Catch all errors to ensure matlab will exit when called from command line.
    try
        iLog = 1; % in case there's an early error to report.
        
        % Set up Matlab path, including some Brainstorm dependencies.
        if isempty(dir('BidsSetPath'))
            MPath = fileparts(mfilename('fullpath'));
            addpath(MPath);
        end
        BidsSetPath;

        if nargin < 6
            BidsOverwrite = [];
        end
        if nargin < 5
            StudyName = [];
        end
        if nargin < 4 || isempty(SaveLog) || ~SaveLog
            iLog = 1;
        else
            % TODO:this is not yet implemented? or not documented.
            iLog = fopen(SaveLog, w);
        end
        if nargin < 3 || isempty(UseSubEmptyroom)
            UseSubEmptyroom = false;
        end
        if nargin < 2 || isempty(Destination)
            Destination = fileparts(AcqDateFolder);
        end
        
        % Find CTF recordings (*.ds) in this folder.
        Recordings = dir(fullfile(AcqDateFolder, '**', '*.ds'));
        % Remove hz.ds
        Recordings(strcmpi({Recordings.name}, 'hz.ds')) = [];
        % for r = 1:numel(Recordings), BidsOverwrite(r).Recording = Recordings(r).name; end;
        % assignin('base', 'BidsOverwrite', BidsOverwrite);
        nR = numel(Recordings);
        
        if ~isempty(BidsOverwrite) 
            if isfield(BidsOverwrite, 'Recording') 
                if numel(BidsOverwrite) == nR
            Overwrite = true;
                else
                    fprintf(iLog, 'User error: BidsOverwrite size (%d) does not match number of recordings found (%d).\n', ...
                        numel(BidsOverwrite), nR);
                    ExitCleanly;
                end
            else
                fprintf(iLog, 'User error: BidsOverwrite not empty but Recording field is missing.\n');
                ExitCleanly;
            end
        else
            Overwrite = false;
        end
        
        % Do all noise recordings first, so that they can be searched when
        % associating them to regular recordings.  Here we are not as
        % specific as later, where the task name must start with "noise".
        isNoise = contains({Recordings(:).name}, {'emptyroom', 'Noise'}, 'IgnoreCase', true);
        iRecs = [find(isNoise), find(~isNoise)];
        
        fprintf(iLog, 'Converting %d MEG recordings to BIDS.\n\n', nR);
        
        for r = iRecs
            % Validate dataset.
            [RecPath, RecName, RecExt] = fileparts(fullfile(Recordings(r).folder, Recordings(r).name));
            fprintf(iLog, '%s\n', [RecName, RecExt]);
            Meg4File = fullfile(RecPath, [RecName, RecExt], [RecName, '.meg4']);
            LockFile = fullfile(RecPath, [RecName, RecExt], '.lock');
            InfoDsFile = fullfile(RecPath, [RecName, RecExt], [RecName, '.infods']);
            AcqFile = fullfile(RecPath, [RecName, RecExt], [RecName, '.acq']);
            % Verify if data file is present and not empty.
            if ~exist(Meg4File, 'file')
                % Check if dataset was renamed manually without renaming internal files.
                Meg4File = dir(fullfile(RecPath, [RecName, RecExt], '*.meg4'));
                if ~isempty(Meg4File)
                    fprintf(iLog, '  Error: Naming mismatch between .ds folder and files.\n');
                else
                    fprintf(iLog, '  Error: Missing data file.\n');
                end
                continue;
            else
                % Check for the presence of .lock file indicating software crashed.
                if exist(LockFile, 'file')
                    Meg4File = dir(Meg4File);
                    if Meg4File.bytes < 9
                        fprintf(iLog, '  Error: Empty dataset from software crash at start of recording.\n');
                        continue;
                    else
                        fprintf(iLog, '  Warning: Incomplete dataset from software crash (usually at end of recording). Some files may be missing.\n');
                    end
                % Check for missing files indicating tuning/calibration dummy datasets.
                elseif ~exist(InfoDsFile, 'file') % DsqSetup tuning
                    fprintf(iLog, '  Skipping dataset with missing .infods, possibly tuning dataset.\n');
                    continue;
                elseif ~exist(AcqFile, 'file') % bias setting calibration
                    fprintf(iLog, '  Skipping dataset with missing .acq, possibly tuning dataset.\n');
                    continue;
                end
            end
            
            % Extract info from dataset name.
            % Recognize different formats: BIDS, CTF.
            
            % BIDS: sub-<label>[_ses-<label>]_task-<label>[_acq-<label>][_run-<index>][_proc-<label>]_meg.<manufacturer_specific_extension>
            [isBids, BidsInfo] = BidsParseRecordingName(Recordings(r).name, iLog, false);
            % If session is empty, acquisition date is used. See below.
            BidsInfo.Study = StudyName;
            % We want to keep our session log files with the raw data.
            % (The BIDS validator still flags some empty CTF-software-generated
            % .bak files.)
            BidsInfo.Ignore = {'*.log'};
                
            % CTF: <subject>_<procedure>_<date>_<task/run>[_AUX].ds
            if ~isBids
                [BidsInfo.Subject, Name] = strtok(Recordings(r).name, '_.');
                % BIDS does not allow dashes in name elements, so remove all.
                BidsInfo.Subject = strrep(BidsInfo.Subject, '-', '');
                Name = strrep(Name, '-', '');
                [BidsInfo.Task, Name] = strtok(Name, '_.'); % Or study
                [BidsInfo.Session, Name] = strtok(Name, '_.');
                [TaskRun, Name] = strtok(Name, '_.'); %#ok<*STTOK>
                BidsInfo.Run = str2double(TaskRun); % NaN if non-numeric (str2num computes expressions, not str2double)
                if isnan(BidsInfo.Run)
                    BidsInfo.Task = [BidsInfo.Task, TaskRun];
                    BidsInfo.Run = [];
                else
                    % [] becomes ''.
                    BidsInfo.Run = sprintf('%02d', BidsInfo.Run);
                end
                % Check for _AUX.ds or other part.
                BidsInfo.Acq = strtok(Name, '_.');
                if strcmpi(BidsInfo.Acq, 'ds')
                    BidsInfo.Acq = [];
                end
            end % Recording format.
            
            %             % Check for additional subfolder that could be the study or subject.
            % In BIDS, would be modality, and not used anyway.
            %             if ~strcmp(Recordings(r).folder, AcqDateFolder)
            %                 if isempty(BidsInfo.Study)
            %                     [~, BidsInfo.Study] = fileparts(Recordings(r).folder);
            %                     % If it matches the subject, disregard.
            %                     if strncmpi(BidsInfo.Study, BidsInfo.Subject, 3)
            %                         BidsInfo.Study = [];
            %                     end
            %                 end
            %             end
            
            if Overwrite && strcmpi(BidsOverwrite(r).Recording, Recordings(r).name)
                for Field = setdiff(fieldnames(BidsOverwrite), 'Recording')'
                    Field = Field{1}; %#ok<FXSET>
                    if strcmp(Field, 'Session') && strcmpi(BidsOverwrite(r).Session, 'Date')
                        % Use scan acquisition date.  Done below.
                        BidsInfo.Session = '';
                    else
                        BidsInfo.(Field) = BidsOverwrite(r).(Field);
                    end
                end
            end

            % Use standard name for noise recordings. Don't just use
            % isNoise because of potential Overwrite info.
            if contains(BidsInfo.Subject, 'emptyroom') || strncmpi(BidsInfo.Task, 'Noise', 5)
                if UseSubEmptyroom
                    BidsInfo.Subject = 'emptyroom';
                end
                % Careful not to try to give same name if run was not a number, e.g. in system test sessions.
                if ~isempty(BidsInfo.Run) || strcmpi(TaskRun, 'noise')
                    BidsInfo.Task = 'noise';
                % else already joined noise and TaskRun text.
                end
            end
            
            % Standardize resting state task names.  BIDS prescribes: "(for resting state use the rest prefix)"
            RestSynonyms = {'Spontaneous', 'Restingstate', 'Baselinerest', 'Resting', 'Rest', ...
                'spontaneous', 'restingstate', 'baselinerest', 'restbaseline', 'resting', ...
                'rest'};
            if contains(BidsInfo.Task, RestSynonyms, 'IgnoreCase', true)
                for iSyn = 1:numel(RestSynonyms)
                    BidsInfo.Task = strrep(BidsInfo.Task, RestSynonyms{iSyn}, '');
                end
                BidsInfo.Task = [RestSynonyms{end}, BidsInfo.Task];
            end
            
            % Use acquisition date/time as session name for noise or if missing.
            if isempty(BidsInfo.Session) || strcmp(BidsInfo.Subject, 'emptyroom')
                % Get acquisition time.
                Res4 = Bids_ctf_read_res4(fullfile(RecPath, [RecName, RecExt], [RecName, '.res4']));
                ScanDate = datetime([Res4.res4.data_date, ' ', Res4.res4.data_time]);
                if ScanDate == datetime('1900-01-01 00:00:00') % Acq date not set bug.
                    % This will be reported later.
                    %fprintf(iLog, '  Warning: Acquisition date not set in res4 file (known bug).\n');
                    InfoDs = CPersistToStruct(readCPersist(InfoDsFile, 0));
                    ScanDate = datetime(InfoDs.DATASET_INFO.DATASET_COLLECTIONDATETIME, 'InputFormat', 'yyyyMMddhhmmss');
                end
                if strcmp(BidsInfo.Subject, 'emptyroom')
                    % Use time to avoid collisions.
                    BidsInfo.Session = datestr(ScanDate, 'yyyymmddTHHMM');
                else
                    BidsInfo.Session = datestr(ScanDate, 'yyyymmdd');
                end
            end
            
            % Convert single CTF dataset and adjoining files to BIDS structure.
            DsToBids(fullfile(Recordings(r).folder, Recordings(r).name), ...
                Destination, BidsInfo);
            
        end % Recordings loop
        
        % Remove empty folder.
        RemainingFiles = dir(AcqDateFolder);
        if ~isempty(RemainingFiles)
            % Implies folder exists.
            RemainingFiles(strcmpi({RemainingFiles.name}, '.')) = [];
            RemainingFiles(strcmpi({RemainingFiles.name}, '..')) = [];
            if isempty(RemainingFiles)
                [Status, Msg] = rmdir(AcqDateFolder);
                if ~Status
                    disp(Msg);
                end
            end
        end
        
    catch ME
        fprintf(iLog, '**%s\n', ME.message);
        for s = 1:numel(ME.stack)
            fprintf(iLog, '  %s line %d\n', ME.stack(s).name, ME.stack(s).line);
        end
    end 
   
    ExitCleanly;
    
    function ExitCleanly()
        % Close log file
        if iLog > 2
            fclose(iLog);
        end
        
        % Exit Matlab
        
        % If the script is run from the cronjob (no gui), then
        % execute an exit so matlab will close
        if usejava('jvm') && ~feature('ShowFigureWindows')
            exit;
        end
    end
    
end

