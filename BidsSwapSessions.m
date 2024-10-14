function BidsSwapSessions(BidsSubjectFolder, Ses1, Ses2)
% Swap two session names (usually numbers).
%
% Both full session names must be given, without 'ses-', as char.

warning('This seems still buggy, verify after!');
if ~ischar(Ses1) || ~ischar(Ses2)
    error('Both full session names must be given, but without "ses-" and as character arrays.');
end

isFull = true;
% Temporary session name.
SesTemp = 'temp';
% Check how many MEG recordings there are to minimize renaming them.
nRec1 = numel(dir(fullfile(BidsSubjectFolder, Ses1, '**', '*.ds')));
nRec2 = numel(dir(fullfile(BidsSubjectFolder, Ses2, '**', '*.ds')));
if nRec1 <= nRec2
    BidsRenameSession(BidsSubjectFolder, Ses1, SesTemp, isFull);
    BidsRenameSession(BidsSubjectFolder, Ses2, Ses1, isFull);
    BidsRenameSession(BidsSubjectFolder, SesTemp, Ses2, isFull);
else
    BidsRenameSession(BidsSubjectFolder, Ses2, SesTemp, isFull);
    BidsRenameSession(BidsSubjectFolder, Ses1, Ses2, isFull);
    BidsRenameSession(BidsSubjectFolder, SesTemp, Ses1, isFull);
end

end

% % This was more efficient but did not work for matching sub-datasets.
% function BidsSwapSessions(BidsSubjectFolder, Ses1, Ses2)
% % Swap two session names (usually numbers).
% %
% % Both session names must be given, without 'sub-'.
% 
% BidsSetPath;
% 
% isFull = true;
% % Temporary folder next to sessions.
% Temp = fullfile(BidsSubjectFolder, 'sub-temp');
% mkdir(Temp);
% [isOk, Message] = movefile(fullfile(BidsSubjectFolder, ['ses-' Ses1]), Temp);
% if ~isOk, error(Message); end
% BidsRenameSession(BidsSubjectFolder, Ses2, Ses1, isFull);
% BidsRenameSession(Temp, Ses1, Ses2, isFull);
% [isOk, Message] = movefile(fullfile(Temp, ['ses-' Ses2]), BidsSubjectFolder);
% if ~isOk, error(Message); end
% rmdir(Temp);
% 
% end