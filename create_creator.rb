puts("connect to cs348")

class Field
  attr_reader :parts, :generator
  def initialize(parts, generator)
    @parts = parts
    @generator = generator
  end

  def generate
    values = {}
    @parts.zip(generator.call()).each{|p,v| values[p]=v}
    values
  end

  class << self
    def combinator(name, *sets)
      head = sets.shift
      new([name], lambda do
        [head.sample % sets.collect(&:sample)]
      end)
    end
    def table_sampler(table, parts)
      new(parts, lambda do
        item = table.entries.sample
        item.values.values_at(*parts)
      end)
    end
    def index(parts)
      index = 0
      new(parts, lambda{index += 1; parts.collect{index}})
    end
    def rand_num(parts, min, max)
      new(parts, lambda{val = rand(max-min)+min; parts.collect{val}})
    end
  end
end

class Table
  attr_reader :name, :fields, :entries
  def initialize(name, definition, fields)
    @name = name
    @definition = definition.gsub(/\n/,"")
    @fields = fields
    @entries = []
  end
  def primary_key(*fields)
    comparator = lambda {|e| fields.collect{|f| e.values[f]}}
    @entries.uniq!(&comparator)
    @entries.sort_by!(&comparator)
  end
  def make_entry
    add_entry(@fields.collect(&:generate).inject({}, &:merge))
  end
  def add_entry(values)
    @entries << (entry = Entry.new(self, values))
    entry
  end
  def create_statement
    <<-DATA.gsub('"',"'")
drop table #@name
create table #@name ( \\
 #@definition)
#{@entries.collect(&:insert_statement).join("\n")}
    DATA
  end
end

class Entry
  attr_reader :values
  def initialize(table, values)
    @table = table
    @values = values
  end
  def insert_statement
    "insert into #{@table.name} values (#{ordered_values.collect(&:inspect).join(',')})"
  end
  def ordered_values
    @table.fields.collect_concat{|field| field.parts.collect{|p| @values[p]}}
  end
end

course_name = Field.combinator(:cname, ["Introduction to %s", "History of %s", "%s and Computation", "%s and Society", "%s: A Retrospective"], ["Databases", "Tire Recycling", "Line Dancing", "Excel", "Pointillism", "Sexism"])

course_number = Field.combinator(:cnum, %w[CS%s EV%s EN%s AR%s AC%s CO%s CM%s MA%s], %w[101 201 300 235 123 221 245 320 119 265])

course = Table.new(:course, <<TABLE_DEF, [course_number, course_name])
cnum        varchar(5) not null, 
cname       varchar(40) not null, 
primary key (cnum)
TABLE_DEF

cs348 = course.add_entry(:cname => 'Introduction to Databases', :cnum => 'CS348')

40.times{course.make_entry}

course.primary_key(:cnum)
course.entries.sort_by!{|e|e.values[:cnum]}

course_ref = Field.table_sampler(course, [:cnum])

puts(course.create_statement)

last_names = %w(Weddell Ilyas Baranov Ng Price Raval Smith Jones Gomez Gross)
first_names = %w(Grant Bob Joe Fred Melvin Roger Peter KillBot)

professor = Table.new(:professor, <<TABLE_DEF, [Field.index([:pnum]), Field.combinator(:pname, ["%s, %s"], last_names, first_names), Field.combinator(:office, %w[MC%s DC%s RCH%s DWE%s], [1023, 780, 345, 932, 221, 1411, 442, 121]), Field.combinator(:dept, ["Computer Science", "Environment", "Philosophy", "Arts", "Pure Math"])])
pnum        integer not null,
pname       varchar(20) not null,
office      varchar(10) not null,
dept        varchar(30) not null,
primary key (pnum)
TABLE_DEF

35.times{professor.make_entry}

prof_ref = Field.table_sampler(professor, [:pnum])

puts(professor.create_statement)

student = Table.new(:student, <<TABLE_DEF, [Field.index([:snum]), Field.combinator(:sname, ["%s, %s"], last_names, first_names), Field.rand_num([:year], 1, 5)])
snum        integer not null,
sname       varchar(20) not null,
year        integer not null,
primary key (snum)
TABLE_DEF

500.times{student.make_entry}

student_ref = Field.table_sampler(student, [:snum])

puts(student.create_statement)

class_table = Table.new(:class, <<TABLE_DEF, [course_ref, Field.combinator(:term, %w[F%s W%s S%s], (2007..2011).to_a), Field.rand_num([:section], 1, 4), prof_ref])
cnum        varchar(5) not null,
term        varchar(5) not null,
section     integer not null,
pnum        integer not null,
primary key (cnum, term, section),
foreign key (cnum) references course (cnum),
foreign key (pnum) references professor (pnum)
TABLE_DEF

400.times{class_table.make_entry}

4.times do |section|
    class_table.add_entry({:cnum => 'CS348', :term => 'F2011', :section => section+1}.merge(prof_ref.generate))
end

class_table.primary_key(:cnum, :term, :section)

class_ref = Field.table_sampler(class_table, [:cnum, :term, :section])

puts(class_table.create_statement)

enrollment = Table.new(:enrollment, <<TABLE_DEF, [student_ref, class_ref])
snum        integer not null,
cnum        varchar(5) not null,
term        varchar(5) not null,
section     integer not null,
primary key (snum, cnum, term, section),
foreign key (snum) references student (snum),
foreign key (cnum, term, section) references class (cnum, term, section) 
TABLE_DEF

1500.times{enrollment.make_entry}

enrollment.primary_key(:snum, :cnum, :term, :section)

enrollment_ref = Field.table_sampler(enrollment, [:snum, :cnum, :term, :section])

puts(enrollment.create_statement)

mark = Table.new(:mark, <<TABLE_DEF, [enrollment_ref, Field.rand_num([:grade], 45, 100)])
snum        integer not null,
cnum        varchar(5) not null,
term        varchar(5) not null,
section     integer not null,
grade       integer not null,
primary key (snum, cnum, term, section),
foreign key (snum, cnum, term, section)
references enrollment (snum, cnum, term, section)
TABLE_DEF

enrollment.entries.each do |entry|
  values = entry.values
  next if values[:term] == 'F2011'
  data = {:grade => rand(60) + 41}
  [:snum, :cnum, :term, :section].each{|k| data[k]=values[k]}
  mark.add_entry(data)
end

mark.primary_key(:snum, :cnum, :term, :section)

puts(mark.create_statement)

schedule = Table.new(:schedule, <<TABLE_DEF, [class_ref, Field.combinator(:day, %w[Monday Tuesday Wednesday Thursday Friday]), Field.combinator(:time, %w(%02d:%02d), (6..18).to_a), Field.combinator(:room, %w[MC%s DWE%s RCH%s DC%s PAS%s], %w[100 115 120 200 203 230 300 340 400 438 459 652])])
cnum        varchar(5) not null,
term        varchar(5) not null,
section     integer not null,
day         varchar(10) not null,
time        varchar(5) not null,
room        varchar(10) not null,
primary key (cnum, term, section, day, time),
foreign key (cnum, term, section)
references class (cnum, term, section)
TABLE_DEF

class_table.entries.each do |entry|
  values = entry.values
  (rand(3)+1).times do
      data = {
        :day => %w[Monday Tuesday Wednesday Thursday Friday].sample,
        :time => "%02d:00" % (rand(13) + 6),
        :room => %w[MC DWE RCH DC PAS].sample + %w[100 115 120 200 203 230 300 340 400 438 459 652].sample
      }
      [:cnum, :term, :section].each{|k| data[k]=values[k]}
      schedule.add_entry(data)
  end
end

schedule.primary_key(:cnum, :term, :section, :day, :time)

puts(schedule.create_statement)

puts 'commit work'
