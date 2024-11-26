function Meta(meta)
    ptype = pandoc.utils.type
    if meta['header-includes'] then
        head_inc = meta['header-includes']
        if ptype(head_inc) == 'table' then
            head_inc = pandoc.List:new(head_inc)
        else
            head_inc = pandoc.List:new{head_inc}
        end
    else
        head_inc = pandoc.List:new{}
    end
    head_inc:insert(pandoc.RawBlock('html', 
        '<script src=anchorlinks.js></script>'))
    meta['header-includes'] = head_inc
    return meta
end


