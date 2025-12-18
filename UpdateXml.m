function XmlObj = UpdateXml(XmlObj, Tags, NewVal, NullWarn)
% Update the value of elements specified by Tags.  
% NewVal can be a function handle that will be applied to the current value.

if nargin < 4 || isempty(NullWarn)
    NullWarn = true;
end

Process = isa(NewVal, 'function_handle');
for iTag = 1:numel(Tags)
    List = XmlObj.getElementsByTagName(Tags{iTag});
    for iL = 0:List.getLength-1
        Item = List.item(iL).getFirstChild;
        % Nodes can be null, so with no getData/setData methods.
        % For now, just skip empty nodes but warn if we wanted to write something.
        if isempty(Item)
            if ~isempty(NewVal) && NullWarn
                warning('Null %s tag, new value not written: %s', Tags{iTag}, NewVal);
            end
            continue
        end
        if Process
            Data = char(Item.getData);
            Item.setData(NewVal(Data));
        else
            Item.setData(NewVal);
        end
    end
end

end

