# coding: utf-8
require 'csv'

def todo
  $stderr.puts "TODO at #{caller[1]}"
end


module Okura
  class Tagger
    def initialize dic
      @dic=dic
    end
    attr_reader :dic
    # -> [String]
    def wakati str,mat
      mincost_path=parse(str).mincost_path mat
      return nil if mincost_path.nil?
      return mincost_path.map{|node|node.word.surface}
    end
    # -> Nodes
    def parse str
      chars=str.split(//)
      nodes=Nodes.new(chars.length+2)
      nodes.add(0,Node.mk_bos)
      nodes.add(chars.length+1,Node.mk_eos)
      str.length.times{|i|
        @dic.possible_words(str,i).each{|w|
          nodes.add(i+1,Node.new(w))
        }
      }
      nodes
    end
  end
  class Nodes
    def initialize len
      @begins=(0...len).map{[]}
      @ends=(0...len).map{[]}
    end
    def [](i)
      @begins[i]
    end
    def length
      @begins.length
    end
    # Matrix -> [Node] | nil
    def mincost_path mat
      return [] if length==0
      # calc cost
      self[0].each{|n|
        n.total_cost=n.word.cost
        n.nearest_prev=nil
      }
      (1...length).each{|i|
        prevs=@ends[i-1]
        curs=@begins[i]
        prevs.each{|prev|
          # 途中で行き止まりのNodeはtotal_costが設定されない
          next if prev.total_cost.nil?
          curs.each{|cur|
            join_cost=mat.cost(prev.word.rid,cur.word.lid)
            next if join_cost.nil?
            cost=prev.total_cost+join_cost+cur.word.cost
            if !cur.total_cost || cost < cur.total_cost
              cur.total_cost=cost
              cur.nearest_prev=prev
            end
          }
        }
      }
      # calc mincost path
      ret=[]
      cur=self[-1][0]
      until cur.nil?
        ret.push cur
        cur=cur.nearest_prev
      end
      # TODO: disconnected
      #  return nil unless ...
      # success
      return ret.reverse
    end
    def add i,node
      @begins[i].push node
      @ends[i+node.length-1].push node
    end
  end
  class Node
    def initialize word
      @word=word
      @nearest_prev=nil
      @total_cost=nil
    end
    attr_reader :word
    attr_accessor :nearest_prev
    attr_accessor :total_cost
    def length
      word.surface.length
    end
    def to_s
      "Node(#{word},#{total_cost})"
    end
    def self.mk_bos
      node=Node.new Word.new('BOS',0,0,0)
      node.total_cost=0
      def node.length; 1; end
      node
    end
    def self.mk_eos
      node=Node.new Word.new('EOS',0,0,0)
      def node.length; 1; end
      node
    end
  end
  class Word
    def initialize surface,lid,rid,cost
      @surface,@lid,@rid,@cost=surface,lid,rid,cost
    end
    attr_reader :surface
    attr_reader :lid
    attr_reader :rid
    attr_reader :cost
    def == other
      return [surface,lid,rid,cost] ==
        [other.surface,other.lid,other.rid,other.cost]
    end
    def to_s
      "Word(#{surface},#{lid},#{rid},#{cost})"
    end
  end
  class Feature
    def initialize id,text
      @id,@text=id,text
    end
    attr_reader :id
    attr_reader :text
    def to_s
      "Feature(#{id},#{text})"
    end
  end
  class Features
    def initialize
      @map_id={}
    end
    def from_id id
      @map_id[id]
    end
    def add feature
      @map_id[feature.id]=feature
    end
    def size
      @map_id.size
    end
    def self.load_from_io io
      fs=Features.new
      io.each_line{|line|
        id_s,name=line.strip.split(/ /,2)
        id=id_s.to_i
        fs.add Feature.new(id,name)
      }
      fs
    end
  end
  def CompositeDic
    def initialize dictionaries
      @dictionaries=dictionaries
    end
    # -> [Word]
    def possible_words str,i
      @dictionaries.map{|dic|dic.possible_words(str,i)}.flatten(1)
    end
  end
  class WordDic
    def initialize
      @size=0
      @root=TrieNode.new
    end
    class TrieNode
      def initialize
        @nodes={}
        @leafs=[]
      end
      def add word,i=0
        if i==word.surface.length
          @leafs.push word
        else
          fst=word.surface[i]
          node=@nodes[fst]
          @nodes[fst]=node=TrieNode.new if node.nil?
          node.add word,i+1
        end
      end
      def find_all str,i,res=Array.new
        res.concat @leafs
        return res unless i < str.length
        node=@nodes[str[i]]
        return res if node.nil?
        node.find_all(str,i+1,res)
        res
      end
    end
    attr_reader :size
    def define word
      @size+=1
      @root.add word
    end
    # -> [Word]
    def possible_words str,i
      @root.find_all str,i
    end
    # IO -> WordDic
    def self.load_from_io io
      wd=WordDic.new
      io.each_line {|line|
        surface,lid_s,rid_s,cost_s,*rest=line.split(/,/,5)
        lid,rid,cost=[lid_s,rid_s,cost_s].map(&:to_i)
        wd.define Word.new(surface,lid,rid,cost)
      }
      wd
    end
  end
  class UnkDic
    # -> [Word]
    def possible_words str,i
      todo
      []
    end
    # -> UnkDic
    def self.load_from_io io
      todo
    end
  end
  class CharTypes
    def initialize
      @types={}
      @mapping={}
      @compat_mapping={}
    end
    def type_for charcode
      @mapping[charcode]||@types['DEFAULT']
    end
    def define_type name,invoke,group,length
      @types[name]=CharType.new(name,invoke,group,length)
    end
    def define_map charcode,type,compat_types
      @mapping[charcode]=type
      type.add charcode
      compat_types.each{|ct|ct.add charcode}
    end
    def named name
      @types[name]
    end
    def self.load_from_io io
      cts=CharTypes.new
      io.each_line{|line|
        cols=line.gsub(/\s*#.*$/,'').split(/\s/)
        next if cols.empty?

        case cols[0]
        when /^0x(\d{4})(?:\.\.0x(\d{4}))?$/
          # mapping
          parse_error line unless cols.size >= 2
          type=cts.named cols[1]
          compat_types=cols[2..-1].map{|name|cts.named name}
          if $2
            ($1.to_i(16)..$2.to_i(16)).each{|c|
              cts.define_map(c,type,compat_types)
            }
          else
            cts.define_map($1.to_i(16),type,compat_types)
          end
        when /^\w+$/
          parse_error line unless cols.size == 4
          # typedef
          cts.define_type cols[0],(cols[1]=='1'),(cols[2]=='1'),Integer(cols[3])
        else
          # error
          parse_error line
        end
      }
      cts
    end
    private
    def self.parse_error line
      raise "Illegal format: #{line}"
    end
  end
  class CharType
    def initialize name,invoke,group,length
      @name,@invoke,@group,@length=name,invoke,group,length
      @accept_charcodes={}
    end
    def add charcode
      @accept_charcodes[charcode]=true
    end
    attr_reader :name
    attr_reader :length
    def group?; @group; end
    def invoke?; @invoke; end
    def accept? charcode
      @accept_charcodes[charcode]
    end
  end
  class Matrix
    def initialize mat
      @mat=mat
    end
    # Feature -> Feature -> Int
    def cost rid,lid
      @mat[rid][lid]
    end
    def set(rid,lid,cost)
      @mat[rid][lid]=cost
    end
    def rsize
      @mat.size
    end
    def lsize
      rsize==0 ? 0 : @mat.first.size
    end
    # -> Matrix
    def self.load_from_io io
      rsize,lsize=io.readline.split(/\s/).map(&:to_i)
      mat_arr=(0...rsize).map{[nil]*lsize}
      io.each_line{|line|
        rid,lid,cost=line.split(/\s/).map(&:to_i)
        mat_arr[rid][lid]=cost
      }
      Matrix.new mat_arr
    end
  end
end
