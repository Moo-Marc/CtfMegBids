function Str = DatetimeToStr(DT, Format)
    % datestr chokes on NaT. Manually set to 'n/a'.
    if nargin < 2 || isempty(Format)
        Format = 'yyyy-mm-ddTHH:MM:SS';
    end    
    Str = cell(size(DT));
    WhereNat = isnat(DT) | isempty(DT);
    Str(WhereNat) = {'n/a'};
    Str(~WhereNat) = cellstr(datestr(DT(~WhereNat), Format)); %datestr returns char array.
end