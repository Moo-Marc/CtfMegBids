function T = BidsMerge(Source, Destination, SortSessions, ZeroPad)
    % Merge two BIDS datasets, renaming sessions in chronological order.
    %
    % We assume that all data aquired on the same date (per subject) is part of
    % the same session.  sub-emptyroom sessions are not renamed.
    %
    % Marc Lalancette 2022-01-31
    
    if nargin < 4 || isempty(ZeroPad)
        ZeroPad = 2;
    elseif ZeroPad < 1
        ZeroPad = 1;
    end
    if nargin < 3 || isempty(SortSessions)
        SortSessions = true;
    end
    if ~exist(Source, 'dir')
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
        T = sortrows(T);
        % Now sorted by subject, then date.

        % Remove emptyroom sessions.
        isEmptyroom = strcmp(T.Subject, 'emptyroom');
        E = T(isEmptyroom, :);
        T(isEmptyroom, :) = [];
    end
    
    for iSes = 1:nT
        if iSes > 1 && strcmp(T.Subject{iSes}, T.Subject(iSes-1))
            if all(ymd(T.Date(iSes)) == ymd(T.Date(iSes-1)))
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
            else
                SesNum = SesNum + 1;
            end
        else
            SesNum = 1;
        end
        T.Session{iSes} = num2str(SesNum, ['%0' num2str(ZeroPad, '%u') 'u']);

        % Rename sessions: directories, files, and inside a few CTF data files.
        if SortSessions && ~strcmp(T.OldSes{iSes}, T.Session{iSes})
            if T.isDest(iSes)
                BidsRenameSession(fullfile(Destination, ['sub-' T.Subject{iSes}]), ...
                    T.OldSes{iSes}, T.Session{iSes});
            else
                BidsRenameSession(fullfile(Source, ['sub-' T.Subject{iSes}]), ...
                    T.OldSes{iSes}, T.Session{iSes});
            end
            % Also rename file in table.
            T.ScansFile{iSes} = replace(T.ScansFile{iSes}, T.OldSes{iSes}, T.Session{iSes});
        end
    end
    
    % Save rename table for updating database later.
    TableFile = fullfile(Destination, sprintf('SessionRenameTableFile_%s.csv', datestr(datetime(), 'yyyy-mm-ddTHHMMSS')));
    writetable(T, TableFile);

    % Prevent overwriting emptyroom sessions without specific time in session name.
    for iSes = 2:numel(E)
        if strcmp(E.OldSes{iSes}, E.OldSes{iSes-1}) && (... % same session name but
                any(ymd(T.Date(iSes)) ~= ymd(T.Date(iSes-1))) || ~contains(E.OldSes{iSes}, 'T') ) % different dates or name doesn't include time
            error('Merging would overwrite an emptyroom session witout specific time in session name. %s\nVerify and manually rename first.', ...
                E.OldSes{iSes});
        end
    end

    % Merge (move source to destination). movefile complains about existing
    % folders, though it overwrites existing files.  copyfile works.
    % This includes sub-emptyroom, which was excluded from renaming.
    if ~isempty(dir(fullfile(Source, 'sub-*'))) % or error
        [IsOk, Message] = copyfile(fullfile(Source, 'sub-*'), Destination, 'f');
        if ~IsOk
            error(Message);
        end
        rmdir(fullfile(Source, 'sub-*'), 's');
    end
    % Also move certain "sub-datasets"
    SubDatasets = {'sourcedata', 'derivatives', 'extras'}; % not .heudiconv
    for iS = 1:numel(SubDatasets)
        if exist(fullfile(Source, SubDatasets{iS}), 'dir')
            [IsOk, Message] = copyfile(fullfile(Source, [SubDatasets{iS} '*']), Destination, 'f');
            if ~IsOk
                error(Message);
            end
            rmdir(fullfile(Source, SubDatasets{iS}), 's');
        end
    end

    function Scans = MergeScansFile(SaveFile, AddFile)
        % Read two BIDS _scans.tsv files and merge them, save into the first one.
        SourceScans = ReadScans(SaveFile);
        DestScans = ReadScans(AddFile);
        Scans = union(SourceScans, DestScans);
        % Sort in chronological order, not required but simplifies comparisons.
        Scans = sortrows(Scans, {'acq_time', 'filename'});
        
        Scans.acq_time = DatetimeToStr(Scans.acq_time);
        writetable(Scans, SaveFile, 'FileType', 'text', 'Delimiter', '\t');
    end

end

