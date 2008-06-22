class AlterDatabaseToRemoveNamespaceFromDataType < ActiveRecord::Migration
  def self.up
    Page.connection.execute "UPDATE pages SET data_type = 'Poll' WHERE data_type = 'Poll::Poll'"
    Page.connection.execute "UPDATE pages SET data_type = 'TaskList' WHERE data_type = 'Task::TaskList'"
  end

  def self.down
    Page.connection.execute "UPDATE pages SET data_type = 'Poll::Poll' WHERE data_type = 'Poll'"
    Page.connection.execute "UPDATE pages SET data_type = 'Task::TaskList' WHERE data_type = 'TaskList'"
  end
end
