function BidsShiftDates(BidsFolder, TrustScans, Subjects)
% Shift session dates per subject for anonymization of BIDS dataset.
%
% Each session's date is compared to its computed shifted date (once at least one session is
% shifted) based on the backup scans.tsv, and shifted if needed.  Do not mix or merge shifted and
% non-shifted recordings within a session.  To add a non shifted recording to a shifted session,
% copy sourcedata/date_shifting.tsv from the shifted dataset to the non-shifted one, shift there,
% then merge.
%
% If TrustScans is set to true, don't verify the date of MEG recordings if
% the corresponding scans.tsv file entry is already shifted. 
%
% BidsFolder must be the root of the BIDS dataset, but specific subjects can be
% specified, as strings e.g. {'sub-0001', 'sub-0002'}.
%
% See the following discussion on specifying date shifting:
%  https://github.com/bids-standard/bids-specification/issues/538
% As a more specific solution is not yet implemented in BIDS, and adding a
% column to scans.tsv would complicate things, for now only include this info in
% scans.json in the BIDS root directory, and in dataset descriptions (readme,
% website, etc.)
%
% Dates only appear inside CTF dataset files (many), and in BIDS scans.tsv
% files. 
%
% To fix shifting errors, e.g. inside MEG files, copy backup scans file and shift again.
%
% Marc Lalancette 1924-10-12
if nargin < 3 
    Subjects = {};
elseif ischar(Subjects)
    Subjects = {Subjects};
elseif ~iscell(Subjects)
    error('Subjects should be specified as a cell array of strings, e.g. {''sub-01'', ''sub-02''}');
end
if nargin < 2 || isempty(TrustScans)
    TrustScans = false;
end

TargetInitialDate = datetime('2000-01-01 12:00:00'); % time is only to avoid rounding to 1999-12-31
BackupFolder = 'sourcedata';

DataDescripFile = fullfile(BidsFolder, 'dataset_description.json');
if ~exist(DataDescripFile, 'file')
    error('BidsFolder should be the BIDS root folder: missing dataset_description.json');
end
% Load "database": for now text file in sourcedata root. Use BIDS style tsv
% table and json description file.
DbFile = fullfile(BidsFolder, BackupFolder, 'date_shifting.tsv');
if ~exist(DbFile, 'file')
    % If not found, create, warn and exit.
    % Specifying type doesn't save it if there's no data, so add a line.
    Db = table('Size', [0, 5], 'VariableTypes', {'cellstr', 'double', 'cellstr', 'datetime', 'datetime'}, ...
        'VariableNames', {'participant_id', 'shift', 'first_scan', 'real_datetime', 'shifted_datetime'});
    Db(1,:) = {'sub-null', NaN, 'null', NaT, NaT};
    SaveDb;
    warning('Date shifting database file not found.  Empty file created: %s.  Verify and run again.', DbFile);
    
    % Table description file.
    JsonFile = [DbFile(1:end-4), '.json'];
    J = struct();
    J.participant_id.Description = 'BIDS subject ID, starting with ''sub-''.';
    J.shift.Description = ['Date difference between the real scan date and the date saved in the data and metadata files ' ...
        'for the corresponding participant. E.g. real date 2020-01-31, saved date 2020-01-01, shift -30'];
    J.shift.Units = 'days';
    J.first_scan.Description = ['Singled-out data file (e.g. first scan for the participant) used to record the real and shifted dates. ' ...
        'Relative path, as saved in scans.tsv files.'];
    J.real_datetime.Description = 'Actual date and time the "first_scan" occured. BIDS format: YYYY-MM-DDThh:mm:ss[.000000][Z].';
    J.shifted_datetime.Description = 'Shifted date and time, resulting from: real_datetime + shift';
    WriteJson(JsonFile, J);
    % Shifting description inside BIDS dataset: single scans.json file in root.
    JsonFile = fullfile(BidsFolder, 'scans.json');
    J = struct();
    J.filename.Description = 'Relative path and file name of each data file (scan) in this session.';
    J.acq_time.Description = ['Shifted date/time at the start of the data collection. ' ...
        'Dates are shifted by an integer number of days for anonymization purposes. Times are unchanged. ' ...
        'The number of days shifted is constant within each subject. Therefore date differences within subject remain valid.'];
    WriteJson(JsonFile, J);
    return;
end

Db = readtable(DbFile, 'FileType', 'text', 'Delimiter', '\t', 'ReadVariableNames', true);

% Get all scans.tsv files in subject folders (since we back them up in sourcedata)
if isempty(Subjects)
    ScansList = dir(fullfile(BidsFolder, 'sub-*', '**', '*_scans.tsv'));
else
    ScansList = [];
    for iSub = 1:numel(Subjects)
        ScansList = [ScansList; dir(fullfile(BidsFolder, Subjects{iSub}, '**', '*_scans.tsv'))]; %#ok<AGROW>
    end
end
nScans = numel(ScansList);

% Catch errors to save database before exiting.
try
    isDbModified = false;
    for iFile = 1:nScans
        % Backup scans file in sourcedata.
        ScansFile = fullfile(ScansList(iFile).folder, ScansList(iFile).name);
        BackupFile = replace(ScansFile, BidsFolder, fullfile(BidsFolder, BackupFolder));
        if ~exist(BackupFile, 'file')
            % Check if session folder exists in backup location.
            BackupPath = fileparts(BackupFile);
            if ~exist(BackupPath, 'dir')
                mkdir(BackupPath);
            end
            [isOk, Msg] = copyfile(ScansFile, BackupFile);
            if ~isOk
                error(Msg);
            end
        end
        % Find subject in database
        Subject = strtok(ScansList(iFile).name, '_');
        iDb = find(strcmp(Db.participant_id, Subject), 1);
        if isempty(iDb)
            iDb = size(Db, 1) + 1;
            % Avoid warning, fill entire row.
            Db(iDb,:) = {Subject, NaN, '', NaT, NaT};
            isDbModified = true;
        end
        Scans = ReadScans(fullfile(ScansList(iFile).folder, ScansList(iFile).name));
        if isempty(Scans)
            warning('Empty scans table: %s', ScansList(iFile).name);
            continue;
        end
        % New in database, or not shifted
        if isnan(Db.shift(iDb)) || Db.shift(iDb) == 0
            % Presume first scan found is earliest one.
            % Unless bugged date < 2001.
            iFirst = 1;
            if Scans.acq_time(iFirst) < TargetInitialDate + years(iFirst)
                if Scans.acq_time(iFirst) < TargetInitialDate - years(iFirst) && iFirst < size(Scans,1)
                    % Probably res4 bug. Try another scan.
                    iFirst = 2;
                    if Scans.acq_time(iFirst) < TargetInitialDate + years(iFirst)
                        error('Bad data dates, maybe res4 bug. %s', ScansList(iFile).name);
                    end
                else
                    % [isOk, Msg] = copyfile(BackupFile, ScansFile);
                    % if ~isOk
                    %     warning(Msg);
                    % end
                    error('Missing in database and/or seems already shifted: %s', ScansList(iFile).name); % Restored backup. (not sure why I wanted to restore here)
                end
            end
            Db.first_scan{iDb} = Scans.filename{iFirst};
            Db.real_datetime(iDb) = Scans.acq_time(iFirst);
            Db.shift(iDb) = round(days(TargetInitialDate - Scans.acq_time(iFirst)));
            Db.shifted_datetime(iDb) = Db.real_datetime(iDb) + days(Db.shift(iDb));
            isDbModified = true;
            % Apply shift and save.
            Shift(Scans, false); % no need to verify
        else
            % Check if needs shifting.
            Shift(Scans, true); % verify
        end
    end

    % Save file
    SaveDb;

catch ME
    SaveDb;
    error(ME.message);
end

% --------------------------------------------------
    function Shift(Scans, Verify)
        % If we don't verify, we shift even if not needed.
        if nargin < 2 || isempty(Verify)
            Verify = true;
        end

        % Apply date shift to scans entries
        ScansBak = ReadScans(BackupFile);
        if Verify
            % Verify "better" with backup date.
            isShift = Scans.acq_time ~= (ScansBak.acq_time + days(Db.shift(iDb)));
            %isShift = abs(days(Scans.acq_time - TargetInitialDate)) > abs(days(Scans.acq_time - Db.real_datetime(iDb)));
        else
            isShift = true(size(Scans, 1), 1);
        end
        if any(isShift)
            Scans.acq_time(isShift) = ScansBak.acq_time(isShift) + days(Db.shift(iDb));
            WriteScans(ScansFile, Scans);
        end
        % Now apply shift to MEG data files.
        for iS = 1:size(Scans, 1)
            % Is it MEG?
            if (~TrustScans || isShift(iS)) && contains(Scans.filename{iS}, '_meg.')
                % Check if date needs changing. If not, presume already fully anonymized.
                [~, RecName] = fileparts(Scans.filename{iS});
                Res4 = Bids_ctf_read_res4(fullfile(ScansList(iFile).folder, Scans.filename{iS}, [RecName, '.res4']));
                Res4Date = datetime([Res4.res4.data_date, ' ', Res4.res4.data_time]);
                if abs(Res4Date - Scans.acq_time(iS)) > hours(1)
                    % > 1h difference, adjust.
                    [NewDate(1),NewDate(2),NewDate(3)] = ymd(Scans.acq_time(iS));
                    Bids_ctf_rename_ds(fullfile(ScansList(iFile).folder, Scans.filename{iS}), [], [], true, NewDate);
                end
            end
        end
    end

    function SaveDb()
        if isDbModified
            fprintf('Saving date shifting database.\n');
            writetable(Db, DbFile, 'FileType', 'text', 'Delimiter', '\t', 'WriteVariableNames', true);
        else
            fprintf('No change in date shifting database.\n');
        end
    end
end



