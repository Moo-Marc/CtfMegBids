function T = BidsMerge(Source, Destination, SortSessions, ZeroPad, SourcedataDate, RenameSourceOnly)
    % Merge two BIDS datasets, renaming sessions in chronological order.
    %
    % Source dataset may be omitted, e.g. to re-order sessions in a single folder.
    % SortSessions [true]: reorder session numbers based on chronological order.
    % SourcedataDate [false]: look for matching scans.tsv under sourcedata, to get original (not
    %   shifted) dates. Warns if original not found, but continues with main scans.tsv in that case,
    %   so can be used with shifted dates in only one of Source or Destination.
    % RenameSourceOnly [false]: make no change to destination folders/files, and rename source
    %   sessions based on dates in destination, giving numbers not in destination to new sessions.
    %
    % We assume that all data aquired on the same date (per subject) is part of
    % the same session.  sub-emptyroom sessions are not renamed.
    %
    % Marc Lalancette 2024-10-08

    
    if nargin < 6 || isempty(RenameSourceOnly)
        RenameSourceOnly = false;
    end
    if nargin < 5 || isempty(SourcedataDate)
        SourcedataDate = false;
    end
    if nargin < 4 || isempty(ZeroPad)
        ZeroPad = 2;
    elseif ZeroPad < 1
        ZeroPad = 1;
    end
    if nargin < 3 || isempty(SortSessions)
        if RenameSourceOnly
            SortSessions = false;
        else
            SortSessions = true;
        end
    end
    if ~SortSessions
        warning('Not sorting sessions is a new feature, verify results.');
    end
    if SortSessions && RenameSourceOnly
        error('Cannot sort sessions when modifying Source only.');
    end
    if isempty(Source) 
        warning('No source directory, only processing destination.')
    elseif ~exist(Source, 'dir')
        error('Source directory not found: %s', Source);
    end
    if ~exist(Destination, 'dir')
        error('Destination directory not found: %s', Destination);
    end
    
    SubDatasets = {'sourcedata', 'derivatives', 'extras'}; % not .heudiconv

    % Get list of subjects and sessions in each.
    Verbose = true;
    S = BidsSessions(Source, Verbose, [], SourcedataDate);
    S.isDest = false(size(S, 1), 1);
    D = BidsSessions(Destination, Verbose, [], SourcedataDate);
    D.isDest = true(size(D, 1), 1);
    if isempty(D)
        error('Destination must exist and contain sessions.');
    end
    if isempty(S)
        warning('Source contains no sessions.');
        T = D;
    else
        T = union(D, S, 'rows');
    end
    T.OldSes = T.Session;
    % For sorting on date only (not times).
    T.Day = dateshift(T.Date, 'start', 'day');
    % nT = size(T, 1);
    % % Must be empty char, not double, for sortrows to work.
    % if SortSessions
    %     T.Session = repmat({''}, nT, 1);
    % end
    T = sortrows(T, {'Subject', 'Day', 'isDest'}, {'ascend', 'ascend', 'descend'});
    % Now sorted by subject, then date, and Destination first when same date.

    % Remove emptyroom sessions.
    isEmptyroom = strcmp(T.Subject, 'emptyroom');
    E = T(isEmptyroom, :);
    T(isEmptyroom, :) = [];
    nT = size(T, 1);
    
    for iSes = 1:nT
        iSameSub = find(strcmp(T.Subject, T.Subject{iSes}));
        if iSes > 1 && strcmp(T.Subject{iSes}, T.Subject(iSes-1))
            if year(T.Date(iSes)) == year(T.Date(iSes-1)) && month(T.Date(iSes)) == month(T.Date(iSes-1)) && ...
                    day(T.Date(iSes)) == day(T.Date(iSes-1))
                % Merge within session, merge _scans.tsv files (and sort).
                % Saved into the source file, which will overwrite the destination file when moving.
                % For subdatasets (e.g. sourcedata), this is done later, just before moving these.
                if T.isDest(iSes)
                    if T.isDest(iSes-1)
                        error('Two sessions with same date in Destination, subject %s', T.Subject{iSes});
                    end
                    if ~RenameSourceOnly
                        MergeScansFile(fullfile(Source, T.ScansFile{iSes-1}), fullfile(Destination, T.ScansFile{iSes}));
                        for iS = 1:numel(SubDatasets)
                            if exist(fullfile(Source, SubDatasets{iS}), 'dir') && exist(fullfile(Destination, SubDatasets{iS}), 'dir') && ...
                                    exist(fullfile(Source, SubDatasets{iS}, T.ScansFile{iSes-1}), 'file')
                                MergeScansFile(fullfile(Source, SubDatasets{iS}, T.ScansFile{iSes-1}), fullfile(Destination, SubDatasets{iS}, T.ScansFile{iSes}));
                            end
                        end
                    end
                else
                    if ~T.isDest(iSes-1)
                        error('Two sessions with same date in Source, subject %s', T.Subject{iSes});
                    end
                    if ~RenameSourceOnly
                        MergeScansFile(fullfile(Source, T.ScansFile{iSes}), fullfile(Destination, T.ScansFile{iSes-1}));
                    end
                end
            else % different session
                if SortSessions
                    SesNum = SesNum + 1;
                else
                    % Verify if duplicated and needs to change. Check before or in destination depending on options
                    iVerifDupl = iSameSub( (~RenameSourceOnly & iSameSub < iSes) | ...
                        (RenameSourceOnly & T.isDest(iSameSub) & iSameSub ~= iSes) );
                    if ismember(T.Session{iSes}, T.Session(iVerifDupl))
                        % Sanity check.
                        if RenameSourceOnly && T.isDest(iSes)
                            disp(T(iSameSub));
                            error('Bug: seems duplicate destination sessions.');
                        end
                        % Find first number not used in this subject.
                        SesNum = 2;
                        while SesNum < 99 % to avoid infinite loop if bugged
                            T.Session{iSes} = num2str(SesNum, ['%0' num2str(ZeroPad, '%u') 'u']);
                            if ismember(T.Session{iSes}, T.Session(iSameSub))
                                SesNum = SesNum + 1;
                            else
                                break;
                            end
                        end
                    end
                end
            end
        else % first session of this subject
            if SortSessions
                SesNum = 1;
            elseif RenameSourceOnly && ~T.isDest(iSes) && ismember(T.Session{iSes}, T.Session(T.isDest(iSameSub)))
                % Find first number not used in this subject.
                SesNum = 2;
                while SesNum < 99 % to avoid infinite loop if bugged
                    T.Session{iSes} = num2str(SesNum, ['%0' num2str(ZeroPad, '%u') 'u']);
                    if ismember(T.Session{iSes}, T.Session(iSameSub))
                        SesNum = SesNum + 1;
                    else
                        break;
                    end
                end
            end
        end

        if SortSessions
            T.Session{iSes} = num2str(SesNum, ['%0' num2str(ZeroPad, '%u') 'u']);
            % Check if that new number already exists on the same side.
            % same subject, not already done, same side, same session string
            iSameSes = iSameSub( iSameSub > iSes & T.isDest(iSameSub) == T.isDest(iSes) & strcmp(T.OldSes(iSameSub), T.Session{iSes}) );
            % isSameSes = strcmp(T.Subject, T.Subject{iSes}) & ((1:nT)' > iSes) & strcmp(T.OldSes, T.Session{iSes}) & T.isDest == T.isDest(iSes);
            if ~isempty(iSameSes)
                % Rename conflicting session number temporarily.
                if numel(iSameSes) > 1
                    disp(T(iSameSub, :));
                    error('Bug: found %d identical sessions?', numel(iSameSes));
                end
                % Rename session.
                if T.isDest(iSameSes)
                    if RenameSourceOnly
                        disp(T(iSameSub, :));
                        error('Bug: ModifySourceOnly but destination session renamed. %d', iSameSes);
                    end
                    BidsRenameSession(fullfile(Destination, ['sub-' T.Subject{iSameSes}]), ...
                        T.OldSes{iSameSes}, [T.OldSes{iSameSes} 'temp'], true);
                else
                    BidsRenameSession(fullfile(Source, ['sub-' T.Subject{iSameSes}]), ...
                        T.OldSes{iSameSes}, [T.OldSes{iSameSes} 'temp'], true);
                end
                % Rename scan file in table.
                T.ScansFile{iSameSes} = replace(T.ScansFile{iSameSes}, ['ses-' T.OldSes{iSameSes}], ['ses-' T.OldSes{iSameSes} 'temp']);
                % Rename old session in table
                T.OldSes{iSameSes} = [T.OldSes{iSameSes} 'temp'];
            end
        end

        % Rename sessions: directories, files, and inside a few CTF data files.
        if ~strcmp(T.OldSes{iSes}, T.Session{iSes})
            if T.isDest(iSes)
                if RenameSourceOnly
                    disp(T(iSes, :));
                    error('Bug: ModifySourceOnly but destination session renamed.');
                end
                BidsRenameSession(fullfile(Destination, ['sub-' T.Subject{iSes}]), ...
                    T.OldSes{iSes}, T.Session{iSes}, true); % full session name
            else
                BidsRenameSession(fullfile(Source, ['sub-' T.Subject{iSes}]), ...
                    T.OldSes{iSes}, T.Session{iSes}, true); % full session name
            end
            % Also rename file in table (unnecessary).
            T.ScansFile{iSes} = replace(T.ScansFile{iSes}, ['ses-' T.OldSes{iSes}], ['ses-' T.Session{iSes}]);
        end
    end
    
    % Save rename table for updating database later.
    if RenameSourceOnly
        TableSaveLoc = fullfile(Source, 'derivatives');
    else
        TableSaveLoc = fullfile(Destination, 'derivatives');
    end
    if ~exist(TableSaveLoc, 'dir')
        mkdir(TableSaveLoc);
    end
    TableFile = fullfile(TableSaveLoc, sprintf('SessionRenameTableFile_%s.csv', datestr(datetime(), 'yyyy-mm-ddTHHMMSS')));
    writetable(T, TableFile);

    % Prevent overwriting emptyroom sessions without specific time in session name.
    for iSes = 2:numel(E)
        if strcmp(E.OldSes{iSes}, E.OldSes{iSes-1}) && (... % same session name but
                year(T.Date(iSes)) ~= year(T.Date(iSes-1)) || month(T.Date(iSes)) ~= month(T.Date(iSes-1)) || day(T.Date(iSes)) ~= day(T.Date(iSes-1)) || ...
                ~contains(E.OldSes{iSes}, 'T') ) % different dates or name doesn't include time
            error('Merging would overwrite an emptyroom session witout specific time in session name. %s\nVerify and manually rename first.', ...
                E.OldSes{iSes});
        end
    end

    % Not merging if only renaming in Source.
    if RenameSourceOnly
        fprintf('Session renaming completed.\n');
        return;
    end

    % Merge (move source to destination). movefile complains about existing folders, 
    % though it overwrites existing files.  copyfile works but wastes time and disk.
    % This includes sub-emptyroom, which was excluded from renaming.
    if ~isempty(dir(fullfile(Source, 'sub-*'))) % or error
        [IsOk, Message] = mergefile(fullfile(Source, 'sub-*'), Destination);
        if ~IsOk, error(Message); end
        %rmdir(fullfile(Source, 'sub-*'));
    end
    % Also move certain "sub-datasets", but only subject folders, in
    % particular to keep the date shifting tsv.
    for iS = 1:numel(SubDatasets)
        if exist(fullfile(Source, SubDatasets{iS}), 'dir')
            if ~exist(fullfile(Destination, SubDatasets{iS}), 'dir')
                [IsOk, Message] = mkdir(fullfile(Destination, SubDatasets{iS}));
                if ~IsOk, error(Message); end
            end
            [IsOk, Message] = mergefile(fullfile(Source, SubDatasets{iS}, 'sub-*'), fullfile(Destination, SubDatasets{iS}));
            if ~IsOk, error(Message); end
            %rmdir(fullfile(Source, SubDatasets{iS}));
        end
    end

    fprintf('Merge completed.\n');

    function Scans = MergeScansFile(SaveFile, AddFile)
        % Read two BIDS _scans.tsv files and merge them, save into the first one.
        % Also checks for wrong variables.
        if ~exist(SaveFile, 'file')
            error('Scans file not found: %s', SaveFile);
        end
        SourceScans = ReadScans(SaveFile);
        Vars = SourceScans.Properties.VariableNames;
        if ~isequal(Vars, {'filename', 'acq_time'})
            if ismember({'filename', 'acq_time'}, Vars)
                SourceScans = SourceScans(:, {'filename', 'acq_time'});
                if numel(Vars) > 2
                    fprintf('Extra columns in scans table ignored: %s\n', SaveFile);
                end
            else
                error('Unexpected scans table variables: %s', SaveFile);
            end
        end
        if ~exist(AddFile, 'file')
            % Nothing to merge.
            Scans = SourceScans;
        else        
            DestScans = ReadScans(AddFile);
            Vars = DestScans.Properties.VariableNames;
            if ~isequal(Vars, {'filename', 'acq_time'})
                if ismember({'filename', 'acq_time'}, Vars)
                    DestScans = DestScans(:, {'filename', 'acq_time'});
                    if numel(Vars) > 2
                        fprintf('Extra columns in scans table ignored: %s\n', AddFile);
                    end
                else
                    error('Unexpected scans table variables: %s', AddFile);
                end
            end
            Scans = union(SourceScans, DestScans);
        end

        % Sort in chronological order, not required but simplifies comparisons.
        Scans = sortrows(Scans, {'acq_time', 'filename'});
        
        Scans.acq_time = DatetimeToStr(Scans.acq_time);
        writetable(Scans, SaveFile, 'FileType', 'text', 'Delimiter', '\t');
    end

end

