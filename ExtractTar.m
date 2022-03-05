function ExtractedFiles = ExtractTar(Tar, Destination)
% Extract all files into Destination folder, ignoring any folder structure in archive.

if ~exist(Destination, 'dir')
    % try creating
    mkdir(Destination);
end
% -C change dir (where to extract)
% --xform syntax is sed. #s#regex#new#mod substitution
% regex is anything from start until filesep: ^.*/
[IsError, Output] = system(sprintf('tar -xf %s -C %s --xform=''s#^.*/##x''', ...
    strrep(Tar, '\', '/'), Destination));
if IsError
    disp(Output);
    error('Tar decompress error: %s', Tar);
end
% Remove extracted directories (all empty).
ExtractedDirs = dir(Destination);
ExtractedFiles = ExtractedDirs(~[ExtractedDirs.isdir]);
ExtractedDirs(~[ExtractedDirs.isdir]) = [];
for iDir = 1:numel(ExtractedDirs)
    if ismember(ExtractedDirs(iDir).name, {'.', '..'})
        continue;
    end
    [IsOk, Message] = rmdir(fullfile(ExtractedDirs(iDir).folder, ExtractedDirs(iDir).name));
    if ~IsOk
        error(Message);
    end
end
delete(Tar);

end