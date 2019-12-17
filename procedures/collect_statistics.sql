create proc dbo.collect_statistics
    @dbName nvarchar(255),
    @debug bit = 0
as
begin
    set nocount on;

    if not exists (select top 1
        1
    from sys.database_mirroring AS m
    where m.database_id = DB_ID(@dbName)
        and (m.mirroring_role_desc ='PRINCIPAL' or m.mirroring_role_desc is null))
    return;

    declare @sql nvarchar(4000),
          @msg nvarchar(4000);

    if (@debug = 1)
  begin
        set @msg = format(getdate(), 'yyyy-MM-dd hh:mm') + ': Update statistics for ' + @dbName;
        raiserror (@msg, 10, 1) WITH NOWAIT;
    end;

    create table #statistics_to_update
    (
        [schema] nvarchar(255),
        table_name nvarchar(255),
        statistics_name nvarchar(255)
    )

    set @sql =
  '
  use [' + @dbName + '];

  insert into #statistics_to_update
    ([schema], table_name, statistics_name)
	select [schema], table_name, statistics_name
	  from
	  (
		  select
			    sch.name as [schema], o.name as table_name, stat.name as statistics_name,
			    case when c.name is null then 1 else 0 end as is_classificator,
			    modification_counter, rows
		    from sys.stats as stat with(nolock)
		    cross apply sys.dm_db_stats_properties(stat.object_id, stat.stats_id) as sp
		    join sys.all_objects o with(nolock)
			    on o.object_id = stat.object_id
			    and type = ''U''
        join sys.schemas sch on sch.schema_id = o.schema_id
		    left join sys.columns c with(nolock)
			    on o.object_id = c.object_id
			    and c.name = ''registered''
	  ) d
	  where (modification_counter * 1.0 / rows > 0.001)
		  or (is_classificator = 0 and modification_counter > 1000);
  ';

    exec sp_executesql @sql;

    declare stats_cursor cursor for
	select [schema], table_name, statistics_name
    from #statistics_to_update;

    declare @schema nvarchar(20), @tableName nvarchar(128), @statisticsName nvarchar(128);

    open stats_cursor;
    fetch next from stats_cursor into @schema, @tableName, @statisticsName;

    while @@fetch_status = 0
  begin
        set @sql = 'use [' + @dbName + ']; update statistics ' + @schema + '.[' + @tableName + '] [' + @statisticsName + '];';

        if (@debug = 1)
    begin
            set @msg = format(getdate(), 'yyyy-MM-dd hh:mm') + ': ' + @sql;
            raiserror (@msg, 10, 1) WITH NOWAIT;
        end;

        exec sp_executesql @sql;

        fetch next from stats_cursor into @schema, @tableName, @statisticsName;
    end

    close stats_cursor;
    deallocate stats_cursor;
    drop table #statistics_to_update;
end