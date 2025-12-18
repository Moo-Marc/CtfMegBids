function Fid = FileOpen(File, Permission)
Fid = fopen(File, Permission);
if Fid < 0
    % Try changing permissions
    system(sprintf('chmod u+rw %s', File));
    Fid = fopen(File, Permission);
    if Fid < 0
        error('Unable to open file %s for %s.', File, Permission);
    end
end
end
