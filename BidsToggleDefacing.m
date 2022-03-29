function BidsToggleDefacing(BidsFolder, isDeface, ContinueFrom)
% Toggle original or defaced T1w scans in BIDS dataset, by copying from sourcedata or derivatives respectively.
%
% isDeface must be present: true to copy defaced images, or false to copy originals.
% Marc Lalancette 2022-03-04

if nargin < 2 || isempty(isDeface)
    error('Missing input arguments.');
end
if ~exist(fullfile(BidsFolder, 'dataset_description.json'), 'file')
    error('Destination should be BIDS root, dataset_description.json not found.');
end

% Verify both sourcedata and derivatives exist.
Source = fullfile(BidsFolder, 'sourcedata');
Deriv = fullfile(BidsFolder, 'derivatives');
if ~exist(Source, 'dir') || ~exist(Deriv, 'dir')
    error('Both sourcedata and derivatives sub-folders should exist in BIDS dataset, and contain original and defaced MRIs respectively.');
end

% Find all MRIs in subject folders.
AnatList = dir(fullfile(BidsFolder, 'sub-*', '**', '*_T1w.nii*'));
nA = numel(AnatList);

if nargin < 3 || isempty(ContinueFrom)
    iStart = 1;
elseif isnumeric(ContinueFrom)
    if ContinueFrom > nA
        error('ContinueFrom index > number of T1w files.');
    end
    iStart = ContinueFrom;
elseif ischar(ContinueFrom)
    iStart = find(contains({AnatList.name}, ContinueFrom), 1);
    if isempty(iStart)
        error('ContinueFrom not found.');
    end
else
    error('ContinueFrom should be subject name or index.');
end

fprintf('Found %d T1w images.\n', nA);
for iA = iStart:nA
    fprintf('%4d  %s\n', iA, AnatList(iA).name);
    % Always confirm both original and defaced exist in sourcedata and derivatives.
    Current = fullfile(AnatList(iA).folder, AnatList(iA).name);
    Original = replace(Current, BidsFolder, Source);
    if ~exist(Original, 'file')
        % Back up if the session looks otherwise ok.  Check json file.
        if exist(replace(Original, {'.nii.gz', '.nii'}, '.json'), 'file')
            [isOk, Message] = copyfile(Current, Original, 'f');
            if ~isOk, error(Message); end
            if ~isDeface
                continue;
            end
        else
            error('Missing backup of original in sourcedata: %s', AnatList(iA).name);
        end
    end
    Defaced = replace(Current, BidsFolder, Deriv);
    % We presume extension is .nii.gz, file won't be found otherwise.
    Defaced = [Defaced(1:end-7), '_full_normfilter.nii.gz'];
    if ~exist(Defaced, 'file')
        error('Missing defaced image in derivatives. Defacing must be done first. %s', AnatList(iA).name);
    end
    if isDeface % Deface
        [isOk, Message] = copyfile(Defaced, Current, 'f');
        if ~isOk, error(Message); end
    else % Restore original
        [isOk, Message] = copyfile(Original, Current, 'f');
        if ~isOk, error(Message); end
    end    
end
