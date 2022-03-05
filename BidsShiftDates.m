function BidsShiftDates(BidsFolder, TrustScans)
% Shift dates per subject for anonymization of BIDS dataset.
%
% See the following discussion on specifying date shifting:
%  https://github.com/bids-standard/bids-specification/issues/538
% As a more specific solution is not yet implemented in BIDS, and adding a
% column to scans.tsv would complicate things, for now only include this info in
% scans.json in the BIDS root directory, and in dataset descriptions (readme,
% website, etc.)
%
% Dates only appear inside CTF dataset files (many), and in BIDS scans.tsv
% files. if TrustScans is set to true, don't verify the date of MEG recordings
% if the corresponding scans.tsv file entry is already shifted.
%
% Marc Lalancette 1922-03-04

if nargin < 2 || isempty(TrustScans)
    TrustScans = false;
end

TargetInitialDate = datetime('2000-01-01 12:00:00'); % time is only to avoid rounding to 1999-12-31
BackupFolder = 'sourcedata';

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
ScansList = dir(fullfile(BidsFolder, 'sub-*', '**', '*_scans.tsv'));
nScans = numel(ScansList);

% Catch errors to save database before exiting.
try

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
        end
        Scans = ReadScans(fullfile(ScansList(iFile).folder, ScansList(iFile).name));
        if isempty(Scans)
            warning('Empty scans table: %s', ScansList(iFile).name);
            continue;
        end
        if isnan(Db.shift(iDb)) || Db.shift(iDb) == 0
            % Presume first scan found is earliest one.
            % Unless bugged date < 2001.
            iFirst = 1;
            if Scans.acq_time(iFirst) < TargetInitialDate + years(iFirst)
                if Scans.acq_time(iFirst) < TargetInitialDate - years(iFirst) && iFirst < size(Scans,1)
                    % Probably res4 bug. Try another scan.
                    iFirst = 2;
                else
                    [isOk, Msg] = copyfile(BackupFile, ScansFile);
                    if ~isOk
                        warning(Msg);
                    end
                    error('Missing in database, seems already shifted. Restored backup. %s', ScansList(iFile).name);
                end
            end
            if Scans.acq_time(iFirst) < TargetInitialDate + years(iFirst)
                error('Bad data dates, maybe res4 bug. %s', ScansList(iFile).name);
            end
            Db.first_scan{iDb} = Scans.filename{1};
            Db.real_datetime(iDb) = Scans.acq_time(1);
            Db.shift(iDb) = round(days(TargetInitialDate - Scans.acq_time(1)));
            Db.shifted_datetime(iDb) = Db.real_datetime(iDb) + days(Db.shift(iDb));
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
        if nargin < 2 || isempty(Verify)
            Verify = true;
        end

        % Apply date shift to scans entries
        if Verify
            isShift = abs(days(Scans.acq_time - TargetInitialDate)) > abs(days(Scans.acq_time - Db.real_datetime(iDb)));
        else
            isShift = true(size(Scans, 1), 1);
        end
        if any(isShift)
            Scans.acq_time(isShift) = Scans.acq_time(isShift) + days(Db.shift(iDb));
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
        fprintf('Saving database.\n');
        writetable(Db, DbFile, 'FileType', 'text', 'Delimiter', '\t', 'WriteVariableNames', true);
    end
end



