function T = BidsMerge(Source, Destination, SortSessions, ZeroPad)
    % Merge two BIDS datasets, renaming sessions in chronological order.
    %
    % We assume that all data aquired on the same date (per subject) is part of
    % the same session.  sub-emptyroom sessions are not renamed.
    %
    % Marc Lalancette 2022-01-31

    % TODO: make it possible to re-order sessions.  Now needs all new session names.
    
    if nargin < 4 || isempty(ZeroPad)
        ZeroPad = 2;
    elseif ZeroPad < 1
        ZeroPad = 1;
    end
    if nargin < 3 || isempty(SortSessions)
        SortSessions = true;
    end
    if isempty(Source) 
        warning('No source directory, only processing destination.')
    elseif ~exist(Source, 'dir')
        error('Source directory not found: %s', Source);
    end
    if ~exist(Destination, 'dir')
        error('Destination directory not found: %s', Destination);
    end
    
    % Get list of subjects and sessions in each.
    S = BidsSessions(Source, true); % verbose
    S.isDest = false(size(S, 1), 1);
    D = BidsSessions(Destination, true); % verbose
    D.isDest = true(size(D, 1), 1);
    if isempty(D)
        error('Destination must exist and contain sessions.');
    end
    if isempty(S)
        warning('Source contains no sessions.');
        T = D;
    else
        T = union(S, D, 'rows');
    end
    nT = size(T, 1);
    if SortSessions
        T.OldSes = T.Session;
        % Must be empty char, not double, for sortrows to work.
        T.Session = repmat({''}, nT, 1);
        T = sortrows(T, {'Subject', 'Date'});
        % Now sorted by subject, then date.

        % Remove emptyroom sessions.
        isEmptyroom = strcmp(T.Subject, 'emptyroom');
        E = T(isEmptyroom, :);
        T(isEmptyroom, :) = [];
        nT = size(T, 1);
    end
    
    for iSes = 1:nT
        if iSes > 1 && strcmp(T.Subject{iSes}, T.Subject(iSes-1))
            if year(T.Date(iSes)) == year(T.Date(iSes-1)) && month(T.Date(iSes)) == month(T.Date(iSes-1)) && ...
                    day(T.Date(iSes)) == day(T.Date(iSes-1))
                % Merge within session, merge _scans.tsv files (and sort).
                % Saved into the source file, which will overwrite the destination file when moving.
                if T.isDest(iSes)
                    if T.isDest(iSes-1)
                        error('Two sessions with same date in Destination, subject %s', T.Subject{iSes});
                    end
                    MergeScansFile(fullfile(Source, T.ScansFile{iSes-1}), fullfile(Destination, T.ScansFile{iSes}));
                else
                    if ~T.isDest(iSes-1)
                        error('Two sessions with same date in Source, subject %s', T.Subject{iSes});
                    end
                    MergeScansFile(fullfile(Source, T.ScansFile{iSes}), fullfile(Destination, T.ScansFile{iSes-1}));
                end
            else % different session
                SesNum = SesNum + 1;
            end
        else
            SesNum = 1;
        end
        T.Session{iSes} = num2str(SesNum, ['%0' num2str(ZeroPad, '%u') 'u']);

        % Check if that new number already exists.
        isSameSes = strcmp(T.Subject, T.Subject{iSes}) & ((1:nT)' > iSes) & strcmp(T.OldSes, T.Session{iSes}) & T.isDest == T.isDest(iSes);
        if any(isSameSes)
            % Rename conflicting session(s) number temporarily.
            for iOldSes = find(isSameSes)
                % Rename session.
                if T.isDest(iOldSes)
                    BidsRenameSession(fullfile(Destination, ['sub-' T.Subject{iOldSes}]), ...
                        T.OldSes{iOldSes}, [T.OldSes{iOldSes} 'temp'], true);
                else
                    BidsRenameSession(fullfile(Source, ['sub-' T.Subject{iOldSes}]), ...
                        T.OldSes{iOldSes}, [T.OldSes{iOldSes} 'temp'], true);
                end
                % Rename scan file in table.
                T.ScansFile{iOldSes} = replace(T.ScansFile{iOldSes}, ['ses-' T.OldSes{iOldSes}], ['ses-' T.OldSes{iOldSes} 'temp']);
                % Rename old session in table
                T.OldSes{iOldSes} = [T.OldSes{iOldSes} 'temp'];
            end
        end
        % Rename sessions: directories, files, and inside a few CTF data files.
        if SortSessions && ~strcmp(T.OldSes{iSes}, T.Session{iSes})
            if T.isDest(iSes)
                BidsRenameSession(fullfile(Destination, ['sub-' T.Subject{iSes}]), ...
                    T.OldSes{iSes}, T.Session{iSes}, true);
            else
                BidsRenameSession(fullfile(Source, ['sub-' T.Subject{iSes}]), ...
                    T.OldSes{iSes}, T.Session{iSes}, true);
            end
            % Also rename file in table (unnecessary).
            T.ScansFile{iSes} = replace(T.ScansFile{iSes}, ['ses-' T.OldSes{iSes}], ['ses-' T.Session{iSes}]);
        end
    end
    
    % Save rename table for updating database later.
    if ~exist(fullfile(Destination, 'derivatives'), 'dir')
        mkdir(fullfile(Destination, 'derivatives'));
    end
    TableFile = fullfile(Destination, 'derivatives', sprintf('SessionRenameTableFile_%s.csv', datestr(datetime(), 'yyyy-mm-ddTHHMMSS')));
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

    % Merge (move source to destination). movefile complains about existing folders, 
    % though it overwrites existing files.  copyfile works but wastes time and disk.
    % This includes sub-emptyroom, which was excluded from renaming.
    if ~isempty(dir(fullfile(Source, 'sub-*'))) % or error
        [IsOk, Message] = mergefile(fullfile(Source, 'sub-*'), Destination);
        if ~IsOk, error(Message); end
        %rmdir(fullfile(Source, 'sub-*'));
    end
    % Also move certain "sub-datasets"
    SubDatasets = {'sourcedata', 'derivatives', 'extras'}; % not .heudiconv
    for iS = 1:numel(SubDatasets)
        if exist(fullfile(Source, SubDatasets{iS}), 'dir')
            [IsOk, Message] = mergefile(fullfile(Source, [SubDatasets{iS} '*']), Destination);
            if ~IsOk, error(Message); end
            %rmdir(fullfile(Source, SubDatasets{iS}));
        end
    end

    function Scans = MergeScansFile(SaveFile, AddFile)
        % Read two BIDS _scans.tsv files and merge them, save into the first one.
        % Also checks for wrong variables.
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
        % Sort in chronological order, not required but simplifies comparisons.
        Scans = sortrows(Scans, {'acq_time', 'filename'});
        
        Scans.acq_time = DatetimeToStr(Scans.acq_time);
        writetable(Scans, SaveFile, 'FileType', 'text', 'Delimiter', '\t');
    end

end

