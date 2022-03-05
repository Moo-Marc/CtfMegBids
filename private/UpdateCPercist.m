function CPersistObj = UpdateCPercist(CPersistObj, Tags, NewVal, NullWarn)
% Update the value of elements specified by Tags.  
% NewVal can be a function handle that will be applied to the current value.

if nargin < 4 || isempty(NullWarn)
    NullWarn = true;
end

Process = isa(NewVal, 'function_handle');
for iTag = 1:numel(Tags)
    isFound = strcmp({CPersistObj.name}, Tags{iTag});
    
    for iF = find(isFound)
        if isempty(CPersistObj(iF)) % should not occur
            if ~isempty(NewVal) && NullWarn
                warning('Null %s tag, new value not written: %s', Tags{iTag}, NewVal);
            end
            continue
        end
        if Process
            Data = char(CPersistObj(iF).data);
            CPersistObj(iF).data = NewVal(Data);
        else
            CPersistObj(iF).data = NewVal;
        end
    end
end

end

