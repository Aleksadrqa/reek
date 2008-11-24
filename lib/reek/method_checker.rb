$:.unshift File.dirname(__FILE__)

require 'reek/checker'
require 'reek/if_context'
require 'reek/yield_call_context'
require 'reek/smells/smells'
require 'reek/object_refs'
require 'set'

module Reek

  class MethodChecker < Checker

    attr_reader :local_variables, :name, :parameters, :num_statements
    attr_reader :instance_variables     # TODO: should be on the class
    attr_reader :calls, :depends_on_self, :refs

    def initialize(smells, klass_name)
      super(smells)
      @class_name = klass_name
      @refs = ObjectRefs.new
      @local_variables = Set.new
      @instance_variables = Set.new
      @parameters = []
      @calls = Hash.new(0)
      @num_statements = 0
      @depends_on_self = false
    end
    
    def description
      "#{@class_name}##{@name}"
    end

    def process_defn(exp)
      name, args = exp[1..2]
      @name = name.to_s
      process(args)
      check_method_properties
      s(exp)
    end

    def process_args(exp)
      Smells::LongParameterList.check(exp, self)
      @parameters = exp[1..-1]
      s(exp)
    end

    def process_attrset(exp)
      @depends_on_self = true if /^@/ === exp[1].to_s
      s(exp)
    end

    def process_lit(exp)
      val = exp[1]
      @depends_on_self = true if val == :self
      s(exp)
    end

    def process_lvar(exp)
      s(exp)
    end

    def process_iter(exp)
      Smells::NestedIterators.check(@inside_an_iter, self)
      cascade_iter(exp)
      s(exp)
    end

    def process_block(exp)
      @num_statements += MethodChecker.count_statements(exp)
      exp[1..-1].each { |s| process(s) }
      s(exp)
    end

    def process_yield(exp)
      handle_context(YieldCallContext, :yield, exp)
    end

    def process_call(exp)
      @calls[exp] += 1
      receiver, meth, args = exp[1..3]
      deal_with_receiver(receiver, meth)
      process(args) if args
      s(exp)
    end

    def process_fcall(exp)
      @depends_on_self = true
      @refs.record_reference_to_self
      process(exp[2]) if exp.length >= 3
      s(exp)
    end

    def process_cfunc(exp)
      @depends_on_self = true
      s(exp)
    end

    def process_vcall(exp)
      @depends_on_self = true
      s(exp)
    end

    def process_if(exp)
      handle_context(IfContext, :if, exp)
    end

    def process_ivar(exp)
      @instance_variables << exp[1]
      @depends_on_self = true
      s(exp)
    end

    def process_gvar(exp)
      s(exp)
    end

    def process_lasgn(exp)
      @local_variables << exp[1]
      process(exp[2])
      s(exp)
    end

    def process_iasgn(exp)
      @instance_variables << exp[1]
      @depends_on_self = true
      process(exp[2])
      s(exp)
    end

    def process_self(exp)
      @depends_on_self = true
      s(exp)
    end

  private

    def self.count_statements(exp)
      result = exp.length - 1
      result -= 1 if Array === exp[1] and exp[1][0] == :args
      result -= 1 if exp[2] == s(:nil)
      result
    end

    def self.is_global_variable?(exp)
      Array === exp and exp[0] == :gvar
    end

    def self.is_override?(class_name, method_name)
      begin
        klass = Object.const_get(class_name)
      rescue
        return false
      end
      return false unless klass.superclass
      klass.superclass.instance_methods.include?(method_name)
    end

    def is_override?
      MethodChecker.is_override?(@class_name, @name)
    end

    def check_method_properties
      @depends_on_self = true if is_override?
      SMELLS[:defn].each {|smell| smell.examine(self, @smells) }
    end

    def cascade_iter(exp)
      process(exp[1])
      @inside_an_iter = true
      exp[2..-1].each { |s| process(s) }
      @inside_an_iter = false
    end

    def deal_with_receiver(receiver, meth)
      @refs.record_ref(receiver) if (receiver[0] == :lvar and meth != :new)
      process(receiver)
    end

    def handle_context(klass, type, exp)
      ctx = klass.new(self, exp)
      exp[1..-1].each {|sub| process(sub)}
      SMELLS[type].each {|smell| smell.examine(ctx, @smells) }
      s(exp)
    end
  end
end
