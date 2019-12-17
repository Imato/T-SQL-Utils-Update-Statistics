create proc dbo.collect_statistics_all
    @debug bit = 0
as
begin
    set nocount on;

    declare @dbs table (name nvarchar(512));

    insert into @dbs
    select d.name
    from sys.databases d
    where name not in ('master', 'tempdb', 'model', 'msdb')
    order by 1;

    declare cur cursor
    for select name
    from @dbs;

    declare @dbName nvarchar(255);

    open cur;
    fetch next from cur into @dbName;

    while @@FETCH_STATUS = 0
  begin
        exec dbo.collect_statistics @dbName = @dbName, @debug = @debug;
        fetch next from cur into @dbName;
    end;

    close cur;
    deallocate cur;
end